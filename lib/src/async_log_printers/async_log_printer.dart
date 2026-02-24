import 'dart:async';

/// A base class for creating log printers that perform asynchronous
/// operations.
///
/// This class ensures that asynchronous logging operations (such as writing to
/// a file, a database, or sending data over a network) are processed
/// sequentially. It uses a [StreamController] to queue incoming messages and
/// processes them one by one using the provided handler function.
///
/// Example usage:
///
/// ```dart
/// final asyncPrinter = AsyncLogPrinter<String>((message) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   print(message);
/// });
///
/// log.printer = asyncPrinter.publisher;
/// ```
base class AsyncLogPrinter<T extends Object?> {
  final _controller = StreamController<T>(sync: true);

  final FutureOr<void> Function(T message) _handler;

  /// Creates an [AsyncLogPrinter] with the specified processing handler.
  ///
  /// The handler is called for each dispatched log message. If it returns a
  /// [Future], subsequent messages will wait in the internal queue until the
  /// [Future] completes, guaranteeing sequential log processing.
  AsyncLogPrinter(this._handler) {
    _controller.stream.asyncMap(_handler).listen((_) {});
  }

  /// Closes the internal stream controller and releases resources.
  ///
  /// This method should be called when the printer is no longer needed
  /// to prevent memory leaks and ensure that the stream is properly closed.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Publishes a new log [message] to be processed by the handler.
  ///
  /// The [message] is added to the internal queue and will be processed
  /// sequentially in the order it was published. This method is typically
  /// assigned to a Logger instance's printer callback.
  void publisher(T message) {
    _controller.add(message);
  }
}
