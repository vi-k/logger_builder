import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';
import 'internal/async_param_publisher.dart';
import 'internal/async_pipeline.dart';

/// A base class for asynchronous publishers that require an additional
/// parameter alongside the log event.
///
/// Implementations of this class queue log events with their associated
/// parameters and process them sequentially, ensuring that logs for the same
/// context are handled properly without race conditions.
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
    Log extends CustomLog> implements Flushable, Closable {
  /// Whether the underlying stream controller delivers events synchronously.
  final bool sync;

  /// Called when [handle] throws.
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

  late final AsyncPipeline<(Param, Log)> _pipeline;

  /// Creates the publisher and starts its processing queue.
  AsyncPublisherWithParamBase({this.sync = false, this.onError}) {
    // In the constructor body rather than an initializer: `handle` is a
    // subclass member, and the pipeline captures `Zone.current` when it is
    // built — which must be the zone that built the publisher, not whichever
    // one happens to publish first.
    _pipeline = AsyncPipeline<(Param, Log)>(
      handle: (entry) => handle(entry.$1, entry.$2),
      sync: sync,
      onError: onError,
    );
  }

  /// Processes a single log event with its bound parameter.
  ///
  /// Events are processed strictly sequentially: the next event is not
  /// handled until the future returned by this method completes.
  FutureOr<void> handle(Param param, Log log);

  /// Whether [close] has been called.
  bool get isClosed => _pipeline.isClosed;

  /// Returns a [CustomLogPublisher] that publishes into this shared queue
  /// with the given [param] attached to every log event.
  ///
  /// The returned publisher also implements [Flushable] and [Closable],
  /// delegating both to this publisher, so it behaves correctly inside
  /// a `MultiPublisher` or a `TransformPublisher`. Because the queue is
  /// shared, closing any adapter closes it for every other adapter too.
  CustomLogPublisher<Log> withParam(Param param) =>
      AsyncParamPublisher(_publish, param, flush, close);

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
  /// subscription, so flushing after every single log is measurably more
  /// expensive than letting the queue drain on its own.
  @override
  Future<void> flush() => _pipeline.flush();

  /// Closes the publisher after processing the already queued log events.
  ///
  /// After closing, publishing throws a [StateError] and [flush] hands back
  /// this same future. Repeated calls return it too.
  ///
  /// Do not await this (or [flush]) from inside [handle]: closing waits for
  /// the running handler to complete, so it would deadlock.
  @override
  Future<void> close() => _pipeline.close();

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
  AsyncPublisherWithParam(this.handler, {super.sync, super.onError});

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
  });

  @override
  FutureOr<void> handle(Param param, Log log) => switch (format(param, log)) {
        final Future<Out> future => future.then((out) => output(param, out)),
        final Out out => output(param, out),
      };
}
