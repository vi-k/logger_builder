import 'dart:async';

import 'package:logger_builder/src/custom_logger/custom_log_publisher.dart';

import '../custom_logger/custom_log.dart';

// ignore: one_member_abstracts
abstract interface class HasFlush {
  Future<void> flush();
}

/// A base class for publishers that process log events asynchronously.
///
/// It provides common functionality for queuing incoming log events via a
/// stream and processing them sequentially, forming the foundation for
/// avoiding blocking operations during application execution.
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
    implements CustomLogPublisher<Log>, HasFlush {
  final bool sync;
  StreamController<Log> _controller;

  AsyncPublisherBase({this.sync = false})
      : _controller = StreamController<Log>(sync: sync) {
    _listen();
  }

  FutureOr<void> handle(Log log);

  @override
  void publish(Log log) {
    if (_controller.isClosed) {
      throw StateError('The publisher is closed');
    }

    _controller.add(log);
  }

  @override
  Future<void> flush() async {
    final oldController = _controller;
    _controller = StreamController<Log>(sync: sync);
    await oldController.close();
    _listen();
  }

  Future<void> close() async {
    await _controller.close();
  }

  void _listen() {
    _controller.stream.asyncMap(handle).listen((_) {});
  }
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
  final FutureOr<void> Function(Log log) handler;

  AsyncPublisher(this.handler, {super.sync});

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
  final FutureOr<Out> Function(Log log) format;
  final FutureOr<void> Function(Out out) output;

  AsyncFormatter({
    required this.format,
    required this.output,
    super.sync,
  });

  @override
  FutureOr<void> handle(Log log) => switch (format(log)) {
        final Out out => output(out),
        final Future<Out> future => future.then(output),
      };
}
