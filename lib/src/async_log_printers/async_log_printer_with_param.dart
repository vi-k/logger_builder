import 'dart:async';

import 'async_log_printer.dart';

/// A base class for creating log printers that perform asynchronous operations
/// and optionally accept a parameter.
///
/// Similar to [AsyncLogPrinter], this class ensures that asynchronous logging
/// operations are processed sequentially. It allows attaching an additional
/// contextual param to publishers, which is then passed alongside the log
/// message to the processing handler.
///
/// Example usage:
/// ```dart
/// final asyncPrinter = AsyncLogPrinterWithParam<String, bool>((message, isError) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   if (isError) {
///     print('Error: $message');
///   } else {
///     print(message);
///   }
/// });
///
/// log.printer = asyncPrinter.publisher(false);
/// log[Levels.error].printer = asyncPrinter.publisher(true);
/// ```
base class AsyncLogPrinterWithParam<T extends Object?, P extends Object?> {
  final _controller = StreamController<(T, P)>(sync: true);

  final FutureOr<void> Function(T message, P param) _handler;

  /// Creates an [AsyncLogPrinterWithParam] with the specified processing
  /// handler.
  ///
  /// The handler is called with both the dispatched log message and the param
  /// supplied when its specific publisher was created. If it returns
  /// a [Future], subsequent messages will wait in the internal queue until the
  /// [Future] completes, guaranteeing sequential log processing.
  AsyncLogPrinterWithParam(this._handler) {
    _controller.stream.asyncMap(_handleMessage).listen((_) {});
  }

  FutureOr<void> _handleMessage((T, P) e) => _handler(e.$1, e.$2);

  /// Closes the internal stream controller and releases resources.
  ///
  /// This method should be called when the printer is no longer needed
  /// to prevent memory leaks and ensure that the stream is properly closed.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Creates a publisher function bound to a specific [param].
  ///
  /// The returned function takes a log message, pairs it with the bound
  /// [param], and adds them to the internal queue for sequential processing.
  /// This created publisher is typically assigned to a Logger instance's
  /// printer callback or used with log-level specific printers.
  void Function(T) publisher(P param) => (message) {
    _controller.add((message, param));
  };
}
