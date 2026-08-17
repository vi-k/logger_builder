import 'dart:async';
import 'dart:collection';

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
/// > [!IMPORTANT]
/// > The buffer is unbounded. If the handler cannot keep up — or keeps
/// > handing batches back through the retry buffer while the sink is down —
/// > the queue grows until the process runs out of memory. There is no
/// > overflow policy and no dropped-log counter; bound the input yourself if
/// > the sink can stall for long. Logs handed back to the retry buffer
/// > *after* [close] was called are dropped silently — logs already queued
/// > when it was called are drained (see [close]).
/// >
/// > The queue is created lazily, on the first [publish], [flush], [close]
/// > or [isClosed], not in the constructor. Without an `onError` the zone
/// > that receives handler errors is therefore the one that touched the
/// > publisher first, not the one that built it.
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
  /// [Zone.handleUncaughtError]. In either case whatever [handle] placed in
  /// the retry buffer is returned to the queue and processing continues —
  /// but only that. Logs the throwing [handle] did not hand back are gone;
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

  late final BufferedPipeline<Log> _pipeline = BufferedPipeline<Log>(
    handle: handle,
    sync: sync,
    onError: onError,
    retryDelay: retryDelay,
  );

  /// Creates the publisher and its buffered processing queue.
  AsyncPublisherWithBufferBase({
    this.sync = false,
    this.onError,
    this.retryDelay = Duration.zero,
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
  AsyncPublisherWithBuffer(
    this.handler, {
    super.sync,
    super.onError,
    super.retryDelay,
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
    super.retryDelay,
  });

  @override
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer) {
    final FutureOr<Out> formatted;
    try {
      formatted = format(logs, retryBuffer);
    } on Object {
      // A throwing format leaves the caller no point at which it could hand
      // the batch back, so retry it wholesale rather than dropping it.
      _retryWholeBatch(logs, retryBuffer);
      rethrow;
    }

    if (formatted is Future<Out>) {
      return formatted.then(
        (out) => output(out, _remainingLogs(logs, retryBuffer), retryBuffer),
        onError: (Object error, StackTrace stackTrace) {
          _retryWholeBatch(logs, retryBuffer);
          Error.throwWithStackTrace(error, stackTrace);
        },
      );
    }

    return output(formatted, _remainingLogs(logs, retryBuffer), retryBuffer);
  }

  /// The retry buffer can only ever hold logs from this batch, so restoring
  /// the whole batch means replacing whatever [format] managed to add.
  void _retryWholeBatch(List<Log> logs, List<Log> retryBuffer) {
    retryBuffer
      ..clear()
      ..addAll(logs);
  }

  List<Log> _remainingLogs(List<Log> logs, List<Log> retryBuffer) {
    if (retryBuffer.isEmpty) {
      return logs;
    }

    // Counted, not a set: a batch may legitimately hold the same log twice,
    // and handing one copy back must not withdraw the other from [output].
    final retried = HashMap<Log, int>.identity();
    for (final log in retryBuffer) {
      retried[log] = (retried[log] ?? 0) + 1;
    }

    final remaining = <Log>[];
    for (final log in logs) {
      final count = retried[log] ?? 0;
      if (count > 0) {
        retried[log] = count - 1;
      } else {
        remaining.add(log);
      }
    }

    return remaining;
  }
}
