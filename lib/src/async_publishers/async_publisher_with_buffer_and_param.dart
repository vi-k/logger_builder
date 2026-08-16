import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';
import 'internal/async_param_publisher.dart';
import 'internal/buffered_pipeline.dart';

/// A base class for asynchronous publishers that buffer logs alongside
/// contextual parameters, emitting batches of parameter-log pairs.
///
/// This bridges the batched workflow of buffer-based publishers with the
/// contextual routing of parameter-based publishers.
///
/// Example usage:
///
/// ```dart
/// final class MetricsPublisher extends AsyncPublisherWithBufferAndParamBase<String, Log> {
///   @override
///   Future<void> handle(
///     List<(String, Log)> entries,
///     List<(String, Log)> retryBuffer,
///   ) async {
///     try {
///       await metricsClient.sendBatch(entries); // entries are a list of (String source, Log log)
///     } catch (e) {
///       retryBuffer.addAll(entries); // Queue failed logs back for next flush
///     }
///   }
/// }
///
/// log.publisher = asyncPublisher.withParam(source);
/// ```
abstract base class AsyncPublisherWithBufferAndParamBase<Param extends Object?,
    Log extends CustomLog> implements Flushable, Closable {
  /// Whether the underlying stream controller delivers events synchronously.
  final bool sync;

  /// Called when [handle] throws.
  ///
  /// When `null`, the error is reported to the current zone via
  /// [Zone.handleUncaughtError]. In either case the retry buffer contents
  /// are returned to the queue and processing continues.
  ///
  /// Note: in a plain Dart program without an error zone, an uncaught
  /// asynchronous error terminates the isolate by default — and then nothing
  /// keeps processing. Provide [onError] or wrap the app in
  /// [runZonedGuarded].
  final void Function(Object error, StackTrace stackTrace)? onError;

  late final BufferedPipeline<(Param, Log)> _pipeline =
      BufferedPipeline<(Param, Log)>(
    handle: handle,
    sync: sync,
    onError: onError,
  );

  /// Creates the publisher and its buffered processing queue.
  AsyncPublisherWithBufferAndParamBase({this.sync = false, this.onError});

  /// Processes a batch of buffered parameter-log [entries].
  ///
  /// Entries added to [retryBuffer] are placed back at the front of the
  /// queue and retried with the next batch.
  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  );

  /// Whether [close] has been called.
  bool get isClosed => _pipeline.isClosed;

  /// Returns a [CustomLogPublisher] that publishes into this shared buffer
  /// with the given [param] attached to every log event.
  CustomLogPublisher<Log> withParam(Param param) =>
      AsyncParamPublisher(_publish, param);

  /// Completes when the queue has been fully drained.
  ///
  /// Drain semantics: the returned future also waits for logs published
  /// after this call, until the buffer becomes empty. Completes immediately
  /// when the publisher is idle or closed.
  @override
  Future<void> flush() => _pipeline.flush();

  /// Closes the publisher after draining the queue: every log accepted
  /// before closing is processed, including logs published while a batch
  /// was in flight. Entries returned to the retry buffer after closing are
  /// dropped.
  ///
  /// After closing, publishing throws a [StateError] and [flush] completes
  /// immediately. Repeated calls return the same future.
  ///
  /// Do not await this (or [flush]) from inside [handle]: closing waits for
  /// the running batch to complete, so it would deadlock.
  @override
  Future<void> close() => _pipeline.close();

  void _publish(Param param, Log log) => _pipeline.add((param, log));
}

/// An asynchronous publisher that batches log events along with their
/// associated parameters.
///
/// Combines the capabilities of `AsyncPublisherWithBuffer` and
/// `AsyncPublisherWithParam`, processing batches of logs where each log event
/// is paired with an auxiliary parameter for context.
///
/// Example usage:
///
/// ```dart
/// final asyncPublisher = AsyncPublisherWithBufferAndParam<String, Log>((entries, retryBuffer) async {
///   try {
///     await db.insertBatch(entries); // entries are a list of (String collectionName, Log log)
///   } catch (e) {
///     retryBuffer.addAll(entries); // Retry them next time
///   }
/// });
///
/// log.publisher = asyncPublisher.withParam(collectionName);
/// ```
final class AsyncPublisherWithBufferAndParam<Param extends Object?,
        Log extends CustomLog>
    extends AsyncPublisherWithBufferAndParamBase<Param, Log> {
  /// The function that processes a batch of buffered parameter-log entries.
  final FutureOr<void> Function(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) handler;

  /// Creates a publisher backed by [handler].
  AsyncPublisherWithBufferAndParam(this.handler, {super.sync, super.onError});

  @override
  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) =>
      handler(entries, retryBuffer);
}

/// An asynchronous publisher that applies format transformations onto a batch
/// of parameter-log tuples before directing them to an output destination.
///
/// Supports returning unhandled parameter-log pairs during formatting, which
/// will be placed back at the front of the queue for the next batch attempt.
///
/// Example usage:
///
/// ```dart
/// final asyncFormatter = AsyncFormatterWithBufferAndParam<String, Log, Map<String, Object?>>(
///   format: (entries, retryBuffer) async {
///     // Format a batch of parameter-log tuples into a payload map
///     return {'logs': entries.map((e) => {'ctx': e.$1, 'msg': e.$2.message}).toList()};
///   },
///   output: (out, entries, retryBuffer) async {
///     try {
///       await apiClient.postLogs(out);
///     } catch (e) {
///       retryBuffer.addAll(entries); // On failure, put logs back into the retry queue
///     }
///   },
/// );
/// ```
final class AsyncFormatterWithBufferAndParam<Param extends Object?,
        Log extends CustomLog, Out extends Object?>
    extends AsyncPublisherWithBufferAndParamBase<Param, Log> {
  /// Transforms a batch of parameter-log entries into an [Out] object.
  ///
  /// Entries added to the retry buffer during formatting are excluded from
  /// the batch passed to [output] and retried with the next batch.
  final FutureOr<Out> Function(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) format;

  /// Receives the formatted [Out] object along with the entries it covers.
  final FutureOr<void> Function(
    Out out,
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) output;

  /// Creates a publisher that formats batches via [format] and hands the
  /// result to [output].
  AsyncFormatterWithBufferAndParam({
    required this.format,
    required this.output,
    super.sync,
    super.onError,
  });

  @override
  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) =>
      switch (format(entries, retryBuffer)) {
        final Future<Out> future => future.then(
            (out) => output(
              out,
              _remainingEntries(entries, retryBuffer),
              retryBuffer,
            ),
          ),
        final Out out =>
          output(out, _remainingEntries(entries, retryBuffer), retryBuffer),
      };

  List<(Param, Log)> _remainingEntries(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) {
    if (retryBuffer.isEmpty) {
      return entries;
    }

    // Records are compared structurally: `param ==` and `log ==` (identity
    // unless the user's Log overrides `==`).
    final retried = Set.of(retryBuffer);
    return [
      for (final entry in entries)
        if (!retried.contains(entry)) entry,
    ];
  }
}
