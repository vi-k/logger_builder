import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';
import 'async_publisher_with_buffer.dart';
import 'async_publisher_with_param.dart';

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
    Log extends CustomLog> implements HasFlush {
  final bool sync;
  final StreamController<void> _controller;
  List<(Param, Log)> _entries = [];
  Completer<void>? _flushCompleter;

  AsyncPublisherWithBufferAndParamBase({this.sync = false})
      : _controller = StreamController<void>(sync: sync) {
    _controller.stream.asyncMap(_handleData).listen(_next);
  }

  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  );

  CustomLogPublisher<Log> withParam(Param param) =>
      _AsyncParamPublisher(this, param);

  @override
  Future<void> flush() async {
    final completer = _flushCompleter ??= Completer<void>();
    return completer.future;
  }

  Future<void> close() async {
    await _controller.close();
  }

  FutureOr<void> _handleData(void _) {
    final retryBuffer = <(Param, Log)>[];
    final entries = _entries;
    _entries = [];
    if (entries.isNotEmpty) {
      final result = handle(entries, retryBuffer);
      if (result is Future<void>) {
        return result.then((_) {
          _entries.insertAll(0, retryBuffer);
        });
      }

      _entries.insertAll(0, retryBuffer);
    }
  }

  void _next(void _) {
    if (_entries.isNotEmpty) {
      _controller.add(null);
    } else {
      _flushCompleter?.complete();
      _flushCompleter = null;
    }
  }

  void _publish(Param param, Log log) {
    final isEmpty = _entries.isEmpty;
    _entries.add((param, log));
    if (isEmpty) {
      _controller.add(null);
    }
  }
}

/// A [CustomLogPublisher] adapter bridging a fixed parameter with an
/// underlying [AsyncPublisherWithBufferAndParamBase] instance.
final class _AsyncParamPublisher<Param extends Object?, Log extends CustomLog>
    implements CustomLogPublisher<Log> {
  final AsyncPublisherWithBufferAndParamBase<Param, Log> _publisher;
  final Param _param;

  _AsyncParamPublisher(this._publisher, this._param);

  @override
  void publish(Log log) {
    _publisher._publish(_param, log);
  }
}

/// An asynchronous publisher that batches log events along with their
/// associated parameters.
///
/// Combines the capabilities of [AsyncPublisherWithBuffer] and
/// [AsyncPublisherWithParam], processing batches of logs where each log event
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
  final FutureOr<void> Function(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) handler;

  AsyncPublisherWithBufferAndParam(this.handler, {super.sync});

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
  final FutureOr<Out> Function(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) format;

  final FutureOr<void> Function(
    Out out,
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) output;

  AsyncFormatterWithBufferAndParam({
    required this.format,
    required this.output,
    super.sync,
  });

  @override
  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) {
    final out = format(entries, retryBuffer);
    final remainingLogs = List.of(entries)..removeWhere(retryBuffer.contains);

    return switch (out) {
      final Out out => output(out, remainingLogs, retryBuffer),
      final Future<Out> future => future.then(
          (out) => output(out, remainingLogs, retryBuffer),
        ),
    };
  }
}
