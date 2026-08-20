part of 'async_publisher.dart';

/// A base class for asynchronous publishers that require an additional
/// parameter alongside the log event.
///
/// Implementations of this class queue log events with their associated
/// parameters and process them sequentially, ensuring that logs for the same
/// context are handled properly without race conditions.
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
/// final class FilePublisher extends AsyncPublisherWithParamBase<String, Log> {
///   @override
///   Future<void> handle(String filePath, Log log) async {
///     await File(filePath).writeAsString(log.toString(), mode: FileMode.append);
///   }
/// }
///
/// final publisher = FilePublisher();
/// log.publisher = publisher.withParam('app.log');
/// ```
abstract base class AsyncPublisherWithParamBase<Param extends Object?,
        Log extends CustomLog> extends _AsyncFacade<(Param, Log)>
    implements Flushable, Closable {
  /// Called with an entry the queue refused because it was full.
  ///
  /// The log is not published and never will be: [maxQueueSize] was reached
  /// when it arrived. The parameter comes with it, so one adapter's losses
  /// are told apart from its neighbours'.
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
  final void Function(Param param, Log log)? onDropped;

  /// Creates the publisher and starts its processing queue.
  AsyncPublisherWithParamBase({
    super.sync,
    super.onError,
    this.onDropped,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> Function((Param, Log) entry) get _entryHandler => _handleEntry;

  @override
  void Function((Param, Log) entry)? get _droppedHandler {
    if (onDropped case final onDropped?) {
      return (entry) => onDropped(entry.$1, entry.$2);
    }

    return null;
  }

  // A named method rather than an inline arrow: the 3.6.0 analyzer reads
  // `(entry) => handle(...)` as discarding a future, because it infers the
  // closure's return type before it knows the parameter's. An explicit
  // `FutureOr<void>` tells it what the arrow always meant.
  FutureOr<void> _handleEntry((Param, Log) entry) => handle(entry.$1, entry.$2);

  /// Processes a single log event with its bound parameter.
  ///
  /// Events are processed strictly sequentially: the next event is not
  /// handled until the future returned by this method completes.
  FutureOr<void> handle(Param param, Log log);

  /// Returns a [CustomLogPublisher] that publishes into this shared queue
  /// with the given [param] attached to every log event.
  ///
  /// The returned publisher also implements [Flushable] and [Closable],
  /// delegating both to this publisher, so it behaves correctly inside
  /// a `MultiPublisher` or a `TransformPublisher`. Because the queue is
  /// shared, closing any adapter closes it for every other adapter too.
  CustomLogPublisher<Log> withParam(Param param) =>
      AsyncParamPublisher(_publish, param, flush, close);

  void _publish(Param param, Log log) => _pipeline.add((param, log));
}

/// An asynchronous publisher that handles logs paired with a specific
/// parameter.
///
/// Useful for scenarios where a publisher needs some auxiliary parameter that
/// might change or be specific to a certain context (e.g., different output
/// files or connection endpoints), processing requests sequentially.
///
/// Example usage:
///
/// ```dart
/// final asyncPublisher = AsyncPublisherWithParam<String, Log>((filePath, log) async {
///   await File(filePath).writeAsString(log.toString(), mode: FileMode.append);
/// });
///
/// log.publisher = asyncPublisher.withParam('app.log');
/// ```
final class AsyncPublisherWithParam<Param extends Object?,
    Log extends CustomLog> extends AsyncPublisherWithParamBase<Param, Log> {
  /// The function that processes a single log event with its parameter.
  final FutureOr<void> Function(Param param, Log log) handler;

  /// Creates a publisher backed by [handler].
  AsyncPublisherWithParam(
    this.handler, {
    super.sync,
    super.onError,
    super.onDropped,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(Param param, Log log) => handler(param, log);
}

/// An asynchronous publisher that formats a parameter-bound log event before
/// dispatching it to an output handler.
///
/// This provides a two-step pipeline where logs are first asynchronously
/// transformed (e.g., serialized into JSON), and then passed to an output
/// mechanism (e.g., a file writer).
///
/// Example usage:
///
/// ```dart
/// final asyncFormatter = AsyncFormatterWithParam<String, Log, Map<String, Object?>>(
///   format: (filePath, log) async {
///     return {'level': log.levelName, 'message': log.message};
///   },
///   output: (filePath, out) async {
///     // Append transformed log to the specified file
///     await File(filePath).writeAsString('$out\n', mode: FileMode.append);
///   },
/// );
///
/// log.publisher = asyncFormatter.withParam('app.log');
/// ```
final class AsyncFormatterWithParam<
    Param extends Object?,
    Log extends CustomLog,
    Out extends Object?> extends AsyncPublisherWithParamBase<Param, Log> {
  /// Transforms a log event with its parameter into an [Out] object.
  final FutureOr<Out> Function(Param param, Log log) format;

  /// Receives the formatted [Out] object along with the parameter.
  final FutureOr<void> Function(Param param, Out out) output;

  /// Creates a publisher that formats logs via [format] and hands the
  /// result to [output].
  AsyncFormatterWithParam({
    required this.format,
    required this.output,
    super.sync,
    super.onError,
    super.onDropped,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(Param param, Log log) => switch (format(param, log)) {
        final Future<Out> future => future.then((out) => output(param, out)),
        final Out out => output(param, out),
      };
}
