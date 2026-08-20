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
  /// Whether the queue hands an entry to `handle` on the stack of the call
  /// that published it.
  ///
  /// Off by default, and the default is the point of the class: `publish`
  /// returns at once and the work happens on a later turn of the event
  /// loop. With it on, the underlying stream controller is synchronous, so
  /// `handle` starts before `publish` returns — an "asynchronous publisher"
  /// that runs on the logging call's stack. Measured with a handler that
  /// records its own name: `sync: true` gives
  /// `before-publish, handle:x, after-publish`, and `sync: false` gives
  /// `before-publish, after-publish, handle:x`.
  ///
  /// It is here for tests and for handlers that are genuinely cheap and
  /// synchronous, where a turn of the event loop per log is the expensive
  /// part. Two things come with it. A `handle` that throws in this mode
  /// throws where the log was written, which is the zone's documented
  /// behaviour and not something this class intercepts; and Dart's own
  /// warning about synchronous controllers applies — the listener runs
  /// inside `add`, so re-entering the publisher from `handle` is the
  /// caller's problem to avoid.
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
  /// The default is 100 000 events. At a thousand logs a second that is a
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

  late final AsyncPipeline<E> _pipeline;

  _AsyncFacade({
    this.sync = false,
    this.onError,
    this.maxQueueSize = 100000,
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
  /// the running handler to complete, so it would deadlock. Calling it
  /// without awaiting is fine and is the way to shut a publisher down from
  /// its own handler — a sink that discovers it is dead can start the close
  /// and return; the close then waits for that same handler to finish, as
  /// it does for any other.
  Future<void> close() => _pipeline.close();
}

/// A base class for publishers that process log events asynchronously.
///
/// It provides common functionality for queuing incoming log events via a
/// stream and processing them sequentially, forming the foundation for
/// avoiding blocking operations during application execution.
///
/// > [!IMPORTANT]
/// > The queue is bounded: [maxQueueSize] events may be accepted and not
/// > yet handled, 100 000 of them by default. At the limit it is the
/// > *incoming* event that is refused, so a [handle] slower than the rate
/// > of logging costs the newest logs rather than the process. A refused
/// > event goes to [onDropped], and leaving that unset does not hide the
/// > loss — the publisher says so itself. `maxQueueSize: null` gives the
/// > bound up: the queue then grows until memory runs out.
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
  /// when it arrived. Use it to persist the log somewhere durable, or at
  /// least to count what the pressure costs.
  ///
  /// Leaving it unset does not hide the loss: the publisher then says so
  /// itself. The first one prints a line at once; the rest are counted, and
  /// the count is printed by the next loss to arrive more than five seconds
  /// later — widening to a minute while the losses keep coming, and back to
  /// five once they stop — or by [close], whichever comes first.
  ///
  /// There is no timer behind any of that, deliberately: a pending timer is
  /// a live root for the event loop, and a dropped log must not buy the
  /// process five more seconds of life. The consequence is worth knowing.
  /// A burst that ends without a later loss and without a [close] — the
  /// shape a synchronous loop of a hundred thousand logs takes — is
  /// announced by that first line and never counted. Pass
  /// `onDropped: (_) {}` to silence all of it.
  ///
  /// It says it with `print`, which means the application's stdout. For
  /// most programs that is the console and the point; for a program whose
  /// stdout carries a protocol — a CLI with `--json`, a server over stdio —
  /// it is a line in the middle of the stream. Two ways out, and the
  /// package deliberately takes neither by default: `onDropped: (_) {}`,
  /// which drops the losses in silence again, or a `print` of your own —
  /// `print` goes through the current [Zone], so an application that
  /// redirects it redirects this too, and a redirect that throws is caught
  /// rather than passed on to the logging call.
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
