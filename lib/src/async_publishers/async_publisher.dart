import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'internal/async_param_publisher.dart';
import 'internal/async_pipeline.dart';

part 'async_publisher_with_param.dart';

/// An interface for publishers that can be flushed.
///
/// Flushing returns a future that completes when every log event accepted so
/// far (and, for buffered publishers, any events accepted while the flush is
/// in progress) has been processed.
abstract interface class Flushable {
  /// Completes when the publisher's queue has been fully processed.
  Future<void> flush();
}

/// The old name of [Flushable].
@Deprecated('Use Flushable instead')
typedef HasFlush = Flushable;

/// An interface for log-event handlers that can be closed.
///
/// Closing is terminal: after the returned future completes, the handler no
/// longer accepts log events.
abstract interface class Closable {
  /// Closes the handler after processing the already accepted log events.
  Future<void> close();
}

/// The wiring both unbuffered facades sit on: the two knobs, the queue, and
/// the lifecycle around it.
///
/// [E] is whatever the queue carries — the log itself for the log-only
/// facade, a `(Param, Log)` record for the parameterised one.
///
/// Three choices here are about the published docs rather than about the
/// code, and the buffered pair made all three first: the class is private,
/// the two facades are one library through `part`, and no interface is
/// declared even though [flush] and [close] implement one. Why each of them,
/// written out once — `_BufferedFacade` in `async_publisher_with_buffer.dart`.
abstract base class _AsyncFacade<E extends Object?> {
  /// Whether the underlying stream controller delivers events synchronously.
  final bool sync;

  /// Called when `handle` throws.
  ///
  /// When `null`, the error is reported to the current zone via
  /// [Zone.handleUncaughtError]. In either case the queue keeps processing
  /// subsequent log events.
  ///
  /// Note: in a plain Dart program without an error zone, an uncaught
  /// asynchronous error terminates the isolate by default — and then nothing
  /// keeps processing. Provide [onError] or wrap the app in
  /// [runZonedGuarded].
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// The most log events the queue accepts before it starts refusing them.
  ///
  /// Counts what has been accepted and not yet handled: the events waiting
  /// in the queue plus the one being handled right now. At the limit it is
  /// the *incoming* event that is refused — it goes to `onDropped` and never
  /// enters the queue. Everything already accepted is still delivered, so
  /// [flush] and [close] promise exactly what they promised before.
  ///
  /// The default is 10 000 events. At a thousand logs a second that is ten
  /// seconds of a sink that is not draining — an outage rather than a burst.
  ///
  /// `null` gives the bound up on purpose: the queue then grows until the
  /// process runs out of memory. That is the right trade only when the input
  /// is bounded elsewhere and losing a log is worse than dying.
  final int? maxQueueSize;

  late final AsyncPipeline<E> _pipeline;

  _AsyncFacade({
    this.sync = false,
    this.onError,
    this.maxQueueSize = 10000,
  }) : assert(
          maxQueueSize == null || maxQueueSize > 0,
          'maxQueueSize must be null or positive: a queue of zero would '
          'refuse every log',
        ) {
    // In the constructor body rather than an initializer, for two reasons
    // that both matter: [_entryHandler] reaches a subclass member and cannot
    // be torn off in an initializer list, and the pipeline captures
    // `Zone.current` when it is built — which must be the zone that built the
    // publisher, not whichever one happens to publish first.
    _pipeline = AsyncPipeline<E>(
      handle: _entryHandler,
      sync: sync,
      onError: onError,
      onDropped: _droppedHandler,
      maxQueueSize: maxQueueSize,
    );
  }

  /// What the queue calls for every entry.
  ///
  /// The one thing the two facades disagree about, and the reason this is a
  /// function the subclass hands over rather than a method it overrides: the
  /// log-only facade hands the queue its `handle` directly, so the entry
  /// reaches the user's code through the same single call as before this
  /// class existed. The parameterised one unpacks the record first.
  FutureOr<void> Function(E entry) get _entryHandler;

  /// What the queue calls for an entry it refused because it was full.
  ///
  /// A function the subclass hands over rather than a method it overrides,
  /// for the same reason as [_entryHandler]: the two facades disagree about
  /// the shape of the callback the user writes.
  void Function(E entry)? get _droppedHandler;

  /// Whether [close] has been called.
  bool get isClosed => _pipeline.isClosed;

  /// Completes when every log event queued before this call has been
  /// processed.
  ///
  /// While a [close] is draining this returns that same future rather than
  /// an already-completed one — reporting "the queue is empty" while logs
  /// are still in flight would be a false all-clear at exactly the wrong
  /// moment.
  ///
  /// Concurrent calls are serialized: a later flush first waits for the
  /// earlier one and then drains the events queued in between. The internal
  /// queue listener is re-created, but always in the zone this publisher was
  /// constructed in, so flushing does not move where later zone-reported
  /// handler errors land.
  ///
  /// Each call replaces the internal [StreamController] and its
  /// subscription, so flushing after every single log is far more expensive
  /// than letting the queue drain on its own. Measured, per log including
  /// the drain: 152 ns when the queue drains by itself against 1258 ns when
  /// every log is followed by a flush. The buffered publishers are hit
  /// harder still — 50 ns against 1417 — because flushing after each log is
  /// exactly what stops them from batching.
  Future<void> flush() => _pipeline.flush();

  /// Closes the publisher after processing the already queued log events.
  ///
  /// After closing, publishing throws a [StateError] and [flush] hands back
  /// this same future. Repeated calls return it too.
  ///
  /// Do not await this (or [flush]) from inside `handle`: closing waits for
  /// the running handler to complete, so it would deadlock.
  Future<void> close() => _pipeline.close();
}

/// A base class for publishers that process log events asynchronously.
///
/// It provides common functionality for queuing incoming log events via a
/// stream and processing them sequentially, forming the foundation for
/// avoiding blocking operations during application execution.
///
/// > [!IMPORTANT]
/// > The queue is unbounded: if [handle] is slower than the rate of logging,
/// > pending events accumulate until the process runs out of memory. There
/// > is no overflow policy and no dropped-log counter — bound the input
/// > yourself if the destination can stall.
///
/// Example usage:
///
/// ```dart
/// final class FilePublisher extends AsyncPublisherBase<Log> {
///   @override
///   Future<void> handle(Log log) async {
///     // Perform asynchronous file write
///     await file.writeAsString(log.toString(), mode: FileMode.append);
///   }
/// }
/// ```
abstract base class AsyncPublisherBase<Log extends CustomLog>
    extends _AsyncFacade<Log>
    implements CustomLogPublisher<Log>, Flushable, Closable {
  /// Called with a log the queue refused because it was full.
  ///
  /// The log is not published and never will be: [maxQueueSize] was reached
  /// when it arrived. Without this callback the loss leaves no trace — no
  /// error, no counter. Use it to persist the log somewhere durable, or at
  /// least to count what the pressure costs.
  ///
  /// A throwing handler does not derail publishing: its own error goes to
  /// the current zone.
  final void Function(Log log)? onDropped;

  /// Creates the publisher and starts its processing queue.
  AsyncPublisherBase({
    super.sync,
    super.onError,
    this.onDropped,
    super.maxQueueSize,
  });

  /// Processes a single log event.
  ///
  /// Events are processed strictly sequentially: the next event is not
  /// handled until the future returned by this method completes.
  FutureOr<void> handle(Log log);

  @override
  FutureOr<void> Function(Log log) get _entryHandler => handle;

  @override
  void Function(Log log)? get _droppedHandler => onDropped;

  @override
  void publish(Log log) => _pipeline.add(log);
}

/// A publisher that processes log events asynchronously.
///
/// This publisher uses a stream to queue incoming log events and process them
/// sequentially. This is useful when the publishing action is computationally
/// expensive or involves asynchronous I/O (e.g., writing to a file, making
/// a network request), preventing the main application flow from blocking
/// or dropping logs.
///
/// Example usage:
///
/// ```dart
/// final asyncPublisher = AsyncPublisher<Log>((log) async {
///   await Future.delayed(Duration(milliseconds: 100)); // Simulate async work
///   print('Asynchronously processed: $log');
/// });
/// ```
final class AsyncPublisher<Log extends CustomLog>
    extends AsyncPublisherBase<Log> {
  /// The function that processes a single log event.
  final FutureOr<void> Function(Log log) handler;

  /// Creates a publisher backed by [handler].
  AsyncPublisher(
    this.handler, {
    super.sync,
    super.onError,
    super.onDropped,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(Log log) => handler(log);
}

/// An asynchronous publisher that applies format transformations onto a log
/// before directing it to an output destination.
///
/// Logs are first asynchronously transformed into an [Out] object, and then
/// passed to the actual output mechanism. Useful for serializing data or
/// preparing payloads for network calls.
///
/// Example usage:
///
/// ```dart
/// final asyncFormatter = AsyncFormatter<Log, Map<String, Object?>>(
///   format: (log) async {
///     // Asynchronously format the log
///     return {'level': log.levelName, 'message': log.message};
///   },
///   output: (out) async {
///     // Asynchronously output the formatted log
///     await apiClient.post('/logs', data: out);
///   },
/// );
/// ```
final class AsyncFormatter<Log extends CustomLog, Out extends Object?>
    extends AsyncPublisherBase<Log> {
  /// Transforms a log event into an [Out] object.
  final FutureOr<Out> Function(Log log) format;

  /// Receives the formatted [Out] object.
  final FutureOr<void> Function(Out out) output;

  /// Creates a publisher that formats logs via [format] and hands the
  /// result to [output].
  AsyncFormatter({
    required this.format,
    required this.output,
    super.sync,
    super.onError,
    super.onDropped,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(Log log) => switch (format(log)) {
        final Future<Out> future => future.then(output),
        final Out out => output(out),
      };
}
