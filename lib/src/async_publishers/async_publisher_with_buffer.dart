import 'dart:async';

import 'package:logger_builder/logger_builder.dart';

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
    implements CustomLogPublisher<Log>, HasFlush {
  final bool sync;
  final StreamController<void> _controller;
  List<Log> _logs = [];
  Completer<void>? _flushCompleter;

  AsyncPublisherWithBufferBase({this.sync = false})
      : _controller = StreamController<void>(sync: sync) {
    _controller.stream.asyncMap(_handleData).listen(_next);
  }

  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer);

  @override
  void publish(Log log) {
    final isEmpty = _logs.isEmpty;
    _logs.add(log);
    if (isEmpty) {
      _controller.add(null);
    }
  }

  @override
  Future<void> flush() async {
    final completer = _flushCompleter ??= Completer<void>();
    return completer.future;
  }

  Future<void> close() async {
    await _controller.close();
  }

  FutureOr<void> _handleData(void _) {
    final retryBuffer = <Log>[];
    final logs = _logs;
    _logs = [];

    if (logs.isNotEmpty) {
      final result = handle(logs, retryBuffer);
      if (result is Future<void>) {
        return result.then((_) {
          _logs.insertAll(0, retryBuffer);
        });
      }

      _logs.insertAll(0, retryBuffer);
    }
  }

  void _next(void _) {
    if (_logs.isNotEmpty) {
      _controller.add(null);
    } else {
      _flushCompleter?.complete();
      _flushCompleter = null;
    }
  }
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
  final FutureOr<void> Function(List<Log> logs, List<Log> retryBuffer) handler;

  AsyncPublisherWithBuffer(this.handler, {super.sync});

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
  final FutureOr<Out> Function(List<Log> logs, List<Log> retryBuffer) format;
  final FutureOr<void> Function(Out out, List<Log> logs, List<Log> retryBuffer)
      output;

  AsyncFormatterWithBuffer({
    required this.format,
    required this.output,
    super.sync,
  });

  @override
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer) {
    final out = format(logs, retryBuffer);
    final remainingLogs = List.of(logs)..removeWhere(retryBuffer.contains);

    return switch (out) {
      final Out out => output(out, remainingLogs, retryBuffer),
      final Future<Out> future => future.then(
          (out) => output(out, remainingLogs, retryBuffer),
        ),
    };
  }
}
