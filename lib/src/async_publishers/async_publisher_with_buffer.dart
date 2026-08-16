import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';
import 'internal/buffered_pipeline.dart';

/// A base class for asynchronous publishers that buffer log events before
/// processing them together as a batch list.
///
/// Implementations collect logs into an internal list, and flush them in
/// sequences rather than individually, allowing for batch processing logic.
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
    implements CustomLogPublisher<Log>, Flushable, Closable {
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

  late final BufferedPipeline<Log> _pipeline = BufferedPipeline<Log>(
    handle: handle,
    sync: sync,
    onError: onError,
  );

  /// Creates the publisher and its buffered processing queue.
  AsyncPublisherWithBufferBase({this.sync = false, this.onError});

  /// Processes a batch of buffered [logs].
  ///
  /// Logs added to [retryBuffer] are placed back at the front of the queue
  /// and retried with the next batch.
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer);

  /// Whether [close] has been called.
  bool get isClosed => _pipeline.isClosed;

  @override
  void publish(Log log) => _pipeline.add(log);

  /// Completes when the queue has been fully drained.
  ///
  /// Drain semantics: the returned future also waits for logs published
  /// after this call, until the buffer becomes empty. Completes immediately
  /// when the publisher is idle or closed.
  @override
  Future<void> flush() => _pipeline.flush();

  /// Closes the publisher after draining the queue: every log accepted
  /// before closing is processed, including logs published while a batch
  /// was in flight. Logs returned to the retry buffer after closing are
  /// dropped.
  ///
  /// After closing, [publish] throws a [StateError] and [flush] completes
  /// immediately. Repeated calls return the same future.
  ///
  /// Do not await this (or [flush]) from inside [handle]: closing waits for
  /// the running batch to complete, so it would deadlock.
  @override
  Future<void> close() => _pipeline.close();
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
  AsyncPublisherWithBuffer(this.handler, {super.sync, super.onError});

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
  final FutureOr<Out> Function(List<Log> logs, List<Log> retryBuffer) format;

  /// Receives the formatted [Out] object along with the logs it covers.
  final FutureOr<void> Function(Out out, List<Log> logs, List<Log> retryBuffer)
      output;

  /// Creates a publisher that formats batches via [format] and hands the
  /// result to [output].
  AsyncFormatterWithBuffer({
    required this.format,
    required this.output,
    super.sync,
    super.onError,
  });

  @override
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer) =>
      switch (format(logs, retryBuffer)) {
        final Future<Out> future => future.then(
            (out) =>
                output(out, _remainingLogs(logs, retryBuffer), retryBuffer),
          ),
        final Out out =>
          output(out, _remainingLogs(logs, retryBuffer), retryBuffer),
      };

  List<Log> _remainingLogs(List<Log> logs, List<Log> retryBuffer) {
    if (retryBuffer.isEmpty) {
      return logs;
    }

    final retried = Set<Log>.identity()..addAll(retryBuffer);
    return [
      for (final log in logs)
        if (!retried.contains(log)) log,
    ];
  }
}
