import 'dart:async';
import 'dart:collection';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';
import 'internal/async_param_publisher.dart';
import 'internal/batch_format.dart';
import 'internal/buffered_pipeline.dart';

part 'async_publisher_with_buffer_and_param.dart';

/// The wiring both buffered facades sit on: the five knobs, the lazily built
/// batch queue, and the lifecycle around it.
///
/// [E] is whatever the queue carries — the log itself for the log-only
/// facade, a `(Param, Log)` record for the parameterised one.
///
/// Private, and the two facades are one library through `part`, on purpose.
/// A shared base in `internal/` would have to expose the queue through a
/// public member to be reachable from another library, and every public
/// member of a base class shows up on the pub.dev page of the classes users
/// extend. Here the members below are exactly the ones that were duplicated
/// before, and nothing else becomes visible. The unbuffered pair is built
/// the same way, on `_AsyncFacade`.
///
/// It also does not `implement` [Flushable] or [Closable], although it
/// provides both methods and both facades declare both interfaces. Adding
/// the clause here changes the published docs: dartdoc hides this class and
/// hoists its interfaces into every class below, which gave the four
/// concrete publishers an "Implemented types" section they never had and put
/// four new rows in the implementer lists of [Flushable] and [Closable].
/// Leaving it off costs nothing — the facades declare the interfaces, so the
/// compiler still checks these two methods against them.
abstract base class _BufferedFacade<E extends Object?> {
  /// Whether the underlying stream controller delivers events synchronously.
  final bool sync;

  /// Called when [handle] throws.
  ///
  /// When `null`, the error is reported to the current zone via
  /// [Zone.handleUncaughtError]. In either case whatever [handle] placed in
  /// the retry buffer is returned to the queue and processing continues —
  /// but only that. Entries the throwing [handle] did not hand back are gone;
  /// reporting the error does not preserve them.
  ///
  /// Note: in a plain Dart program without an error zone, an uncaught
  /// asynchronous error terminates the isolate by default — and then nothing
  /// keeps processing. Provide [onError] or wrap the app in
  /// [runZonedGuarded].
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// How long to wait before retrying a batch that was handed back through
  /// the retry buffer.
  ///
  /// Applies only after a batch returned entries, so a handler that keeps
  /// up pays nothing. Retries always go through the event loop, never the
  /// microtask queue, so a permanently unavailable sink can no longer starve
  /// timers, I/O or the application's own [close] call — but with the
  /// default [Duration.zero] the queue still retries as fast as the event
  /// loop allows. Set a non-zero value when the sink can be down for a
  /// while.
  final Duration retryDelay;

  /// Called with entries that will never be delivered.
  ///
  /// Three things reach it: an entry the full queue refused (see
  /// [maxQueueSize]), a batch that spends its [maxRetries] budget, and
  /// entries handed back to the retry buffer *after* [close] was called,
  /// which can never be processed. Use it to persist them somewhere
  /// durable, or at least to count them.
  ///
  /// Leaving it unset does not hide the loss: the publisher then says so
  /// itself. The first one prints a line at once, the rest are counted into
  /// a summary at most once every five seconds — widening to a minute while
  /// the losses keep coming, and back to five once they stop. Pass
  /// `onDropped: (_) {}` to silence that.
  ///
  /// A throwing handler does not derail the shutdown: its own error goes to
  /// the current zone.
  final void Function(List<E> entries)? onDropped;

  /// How many times a batch handed back through the retry buffer is
  /// retried before it is dropped.
  ///
  /// Counts a run of failures, not the lifetime of the publisher: a batch
  /// that gets through resets the budget, so a sink that comes back gets
  /// the full allowance again. When the budget is spent the batch goes to
  /// [onDropped] and the queue moves on.
  ///
  /// There is no unbounded setting, and that is the point. Retrying for
  /// ever is not "never lose a log": a deterministically failing batch — a
  /// `toString` that throws, a value that cannot be serialised — is never
  /// delivered and never dropped either, it just holds the queue and burns
  /// a core. Measured before this existed: 242 820 handler calls and as
  /// many [onError] calls in half a second, from one log.
  ///
  /// Zero means a batch that is handed back is dropped at once.
  ///
  /// Together with [retryDelay] this also bounds how long a publisher
  /// nobody closes keeps the isolate alive: a pending retry timer is
  /// a live root for the event loop, so before the budget existed a
  /// worker with a dead sink returned from `main` and never exited.
  /// [close] does not wait any of it out — it cancels the pending
  /// timer and makes one prompt final attempt.
  final int maxRetries;

  /// The most entries the queue accepts before it starts refusing them.
  ///
  /// Counts what has been accepted and not yet finished: the entries waiting
  /// in the queue plus the batch being handled right now. At the limit it is
  /// the *incoming* entry that is refused — it goes to [onDropped] and never
  /// enters the queue. Everything already accepted is still delivered, so
  /// [flush] and [close] promise exactly what they promised before, and a
  /// batch handed back through the retry buffer is never cut: it was
  /// accepted long ago.
  ///
  /// The default is 100 000 entries. At a thousand logs a second that is a
  /// hundred seconds of a sink that is not draining — an outage rather than
  /// a burst — and around 20 MB held, at two hundred bytes a log.
  ///
  /// The queue drains only when the event loop turns, so a synchronous loop
  /// that publishes more than this without awaiting anything loses the rest
  /// however healthy the sink is — nothing has had a chance to run it yet.
  /// That loop, not the outage, is what the default is sized against: this
  /// package's own benchmark publishes 20 000 logs in exactly such a burst,
  /// and the bound carries all of it. A batch job that writes millions of
  /// lines without awaiting still needs a bound of its own, or `null`.
  ///
  /// `null` gives the bound up on purpose: the queue then grows until the
  /// process runs out of memory. That is the right trade only when the input
  /// is bounded elsewhere and losing a log is worse than dying.
  final int? maxQueueSize;

  final Zone _zone = Zone.current;

  BufferedPipeline<E>? _pipelineOrNull;

  BufferedPipeline<E> get _pipeline => _pipelineOrNull ??= BufferedPipeline<E>(
        handle: handle,
        sync: sync,
        onError: onError,
        onDropped: onDropped,
        retryDelay: retryDelay,
        maxRetries: maxRetries,
        maxQueueSize: maxQueueSize,
        zone: _zone,
      );

  _BufferedFacade({
    this.sync = false,
    this.onError,
    this.onDropped,
    this.retryDelay = Duration.zero,
    this.maxRetries = 100,
    this.maxQueueSize = 100000,
  }) : assert(
          maxQueueSize == null || maxQueueSize > 0,
          'maxQueueSize must be null or positive: a queue of zero would '
          'refuse every log',
        );

  /// Processes a batch of buffered [entries].
  ///
  /// Entries added to [retryBuffer] are placed back at the front of the
  /// queue and retried with the next batch.
  FutureOr<void> handle(List<E> entries, List<E> retryBuffer);

  /// Whether [close] has been called.
  ///
  /// Reading this does not create the queue: asking whether a publisher is
  /// closed used to materialise a `StreamController` with a live subscription
  /// nobody would ever close, and pinned the zone that receives handler
  /// errors to whoever asked first.
  bool get isClosed => _pipelineOrNull?.isClosed ?? false;

  /// Completes when the queue has been fully drained.
  ///
  /// Drain semantics: the returned future also waits for logs published
  /// after this call, until the buffer becomes empty. Completes immediately
  /// when the publisher is idle.
  ///
  /// While a [close] is draining this returns that same future rather than an
  /// already-completed one — reporting "the queue is empty" while logs are
  /// still in flight would be a false all-clear at exactly the wrong moment.
  Future<void> flush() => _pipelineOrNull?.flush() ?? Future<void>.value();

  /// Closes the publisher after draining the queue: every entry accepted
  /// before closing is processed, including entries published while a batch
  /// was in flight. Entries returned to the retry buffer after closing are
  /// dropped and handed to [onDropped].
  ///
  /// A retry that was waiting out [retryDelay] is not waited for: the pending
  /// timer is cancelled and one prompt final attempt is made instead, so
  /// shutdown latency does not scale with [retryDelay].
  ///
  /// After closing, publishing throws a [StateError] and [flush] hands back
  /// this same future. Repeated calls return it too.
  ///
  /// Do not await this (or [flush]) from inside [handle]: closing waits for
  /// the running batch to complete, so it would deadlock.
  Future<void> close() => _pipeline.close();
}

/// A base class for asynchronous publishers that buffer log events before
/// processing them together as a batch list.
///
/// Implementations collect logs into an internal list, and flush them in
/// sequences rather than individually, allowing for batch processing logic.
///
/// > [!IMPORTANT]
/// > The buffer is unbounded. If the handler cannot keep up — or keeps
/// > handing batches back through the retry buffer while the sink is down —
/// > the queue grows until the process runs out of memory. There is no
/// > overflow policy; bound the input yourself if the sink can stall for
/// > long. Logs handed back to the retry buffer *after* [close] was called
/// > cannot be processed and are dropped — set [onDropped] to see them.
/// > Logs already queued when [close] was called are drained (see [close]).
/// >
/// > The queue is created lazily, on the first [publish] or [close], not in
/// > the constructor ([flush] and [isClosed] no longer create it). Without an
/// > `onError` the zone that receives handler errors is therefore the one
/// > that published first, not the one that built the publisher.
///
/// Example usage:
///
/// ```dart
/// final class DBBatchPublisher extends AsyncPublisherWithBufferBase<Log> {
///   @override
///   Future<void> handle(List<Log> logs, List<Log> retryBuffer) async {
///     try {
///       await db.insertBatch(logs);
///     } on Object catch (error, stackTrace) {
///       // Return unhandled logs to retry them next time
///       retryBuffer.addAll(logs);
///       errorReport(error, stackTrace);
///     }
///   }
/// }
/// ```
abstract base class AsyncPublisherWithBufferBase<Log extends CustomLog>
    extends _BufferedFacade<Log>
    implements CustomLogPublisher<Log>, Flushable, Closable {
  /// Creates the publisher and its buffered processing queue.
  AsyncPublisherWithBufferBase({
    super.sync,
    super.onError,
    super.onDropped,
    super.retryDelay,
    super.maxRetries,
    super.maxQueueSize,
  });

  /// Processes a batch of buffered [logs].
  ///
  /// Logs added to [retryBuffer] are placed back at the front of the queue
  /// and retried with the next batch.
  ///
  /// > [!IMPORTANT]
  /// > [retryBuffer] is the only way to keep a log. A throwing [handle] —
  /// > synchronously or through its future — does not retry the batch: the
  /// > error is routed to [onError] or the current zone, and every log not
  /// > already handed back is dropped. Wrap the failing work in a
  /// > `try`/`catch` and `retryBuffer.addAll(logs)` there.
  @override
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer);

  @override
  void publish(Log log) => _pipeline.add(log);
}

/// An asynchronous publisher that buffers log events and processes them in
/// batches.
///
/// Instead of processing each log event individually, this publisher collects
/// logs into a buffer and flushes them as a list to its handler. This is
/// optimal for high-throughput environments where batching I/O operations
/// (like database inserts or network uploads) avoids performance bottlenecks.
///
/// Example usage:
///
/// ```dart
/// final asyncPublisher = AsyncPublisherWithBuffer<Log>((logs, retryBuffer) async {
///   try {
///     await db.insertBatch(logs);
///   } on Object catch (error, stackTrace) {
///     // Return unhandled logs to retry them next time
///     retryBuffer.addAll(logs);
///     errorReport(error, stackTrace);
///   }
/// });
/// ```
final class AsyncPublisherWithBuffer<Log extends CustomLog>
    extends AsyncPublisherWithBufferBase<Log> {
  /// The function that processes a batch of buffered logs.
  final FutureOr<void> Function(List<Log> logs, List<Log> retryBuffer) handler;

  /// Creates a publisher backed by [handler].
  AsyncPublisherWithBuffer(
    this.handler, {
    super.sync,
    super.onError,
    super.onDropped,
    super.retryDelay,
    super.maxRetries,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer) =>
      handler(logs, retryBuffer);
}

/// An asynchronous publisher that formats buffered batches of logs before
/// generating output.
///
/// It allows both the translation of a list of logs into a desired structure
/// (e.g., converting log objects into a single HTTP payload), and handles
/// unhandled log retrying if backpressure or failures occur.
///
/// Example usage:
///
/// ```dart
/// final asyncFormatter = AsyncFormatterWithBuffer<Log, String>(
///   format: (logs, retryBuffer) async {
///     // Format a batch of logs into a single newline-separated string
///     return logs.map((log) => log.message).join('\n');
///   },
///   output: (out, logs, retryBuffer) async {
///     try {
///       await apiClient.postLogs(out);
///     } catch (e) {
///       // Assuming a manual rollback system, otherwise return unhandled logs
///       retryBuffer.addAll(logs);
///     }
///   },
/// );
/// ```
final class AsyncFormatterWithBuffer<Log extends CustomLog, Out extends Object?>
    extends AsyncPublisherWithBufferBase<Log> {
  /// Transforms a batch of logs into an [Out] object.
  ///
  /// Logs added to the retry buffer during formatting are excluded from the
  /// batch passed to [output] and retried with the next batch.
  ///
  /// A throwing [format] — synchronously or through its future — puts the
  /// whole batch back into the retry buffer instead of dropping it, and the
  /// error is routed to `onError` or the current zone. There is no other
  /// point at which the caller could hand the batch back: [output] never
  /// runs.
  final FutureOr<Out> Function(List<Log> logs, List<Log> retryBuffer) format;

  /// Receives the formatted [Out] object along with the logs it covers.
  ///
  /// Unlike [format], a throwing [output] does **not** put the batch back:
  /// by the time it runs the sink may already have taken part of the batch,
  /// so retrying wholesale would duplicate deliveries. Only what [output]
  /// itself added to the retry buffer survives; the rest is dropped and the
  /// error goes to `onError` or the current zone. Catch inside [output] and
  /// `retryBuffer.addAll(logs)` when the destination should be retried.
  final FutureOr<void> Function(Out out, List<Log> logs, List<Log> retryBuffer)
      output;

  /// Creates a publisher that formats batches via [format] and hands the
  /// result to [output].
  AsyncFormatterWithBuffer({
    required this.format,
    required this.output,
    super.sync,
    super.onError,
    super.onDropped,
    super.retryDelay,
    super.maxRetries,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer) => handleBatch(
        entries: logs,
        retryBuffer: retryBuffer,
        format: format,
        output: output,
        // Identity: a user's `Log` may define value equality, and two
        // distinct logs that compare equal must not be interchangeable here.
        counter: HashMap<Log, int>.identity,
      );
}
