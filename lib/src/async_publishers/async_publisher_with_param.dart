import 'dart:async';

import 'package:logger_builder/src/custom_logger/custom_log_publisher.dart';

import '../custom_logger/custom_log.dart';
import 'async_publisher.dart';

/// A base class for asynchronous publishers that require an additional
/// parameter alongside the log event.
///
/// Implementations of this class queue log events with their associated
/// parameters and process them sequentially, ensuring that logs for the same
/// context are handled properly without race conditions.
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
    Log extends CustomLog> implements HasFlush {
  final bool sync;
  StreamController<(Param, Log)> _controller;

  AsyncPublisherWithParamBase({this.sync = false})
      : _controller = StreamController<(Param, Log)>(sync: sync) {
    _listen();
  }

  FutureOr<void> handle(Param param, Log log);

  CustomLogPublisher<Log> withParam(Param param) =>
      _AsyncParamPublisher(this, param);

  @override
  Future<void> flush() async {
    final oldController = _controller;
    _controller = StreamController<(Param, Log)>(sync: sync);
    await oldController.close();
    _listen();
  }

  Future<void> close() async {
    await _controller.close();
  }

  void _listen() {
    _controller.stream.asyncMap(_handle).listen((_) {});
  }

  FutureOr<void> _handle((Param, Log) data) => handle(data.$1, data.$2);

  void _publish(Param param, Log log) {
    if (_controller.isClosed) {
      throw StateError('The publisher is closed');
    }

    _controller.add((param, log));
  }
}

/// A simple [CustomLogPublisher] that wraps an [AsyncPublisherWithParamBase],
/// automatically attaching a specific parameter to every log it receives.
final class _AsyncParamPublisher<Param extends Object?, Log extends CustomLog>
    implements CustomLogPublisher<Log> {
  final AsyncPublisherWithParamBase<Param, Log> _publisher;
  final Param _param;

  _AsyncParamPublisher(this._publisher, this._param);

  @override
  void publish(Log log) {
    _publisher._publish(_param, log);
  }
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
  final FutureOr<void> Function(Param param, Log log) handler;

  AsyncPublisherWithParam(this.handler, {super.sync});

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
  final FutureOr<Out> Function(Param param, Log log) format;
  final FutureOr<void> Function(Param param, Out out) output;

  AsyncFormatterWithParam({
    required this.format,
    required this.output,
    super.sync,
  });

  @override
  FutureOr<void> handle(Param param, Log log) => switch (format(param, log)) {
        final Out out => output(param, out),
        final Future<Out> future => future.then((out) => output(param, out)),
      };
}
