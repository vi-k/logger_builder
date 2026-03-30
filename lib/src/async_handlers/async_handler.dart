import 'dart:async';

/// An abstract base class for creating handlers that perform asynchronous
/// operations.
///
/// This class ensures that asynchronous operations are processed sequentially.
/// It uses a [StreamController] to queue incoming data and processes them
/// one by one using the [handle] method.
///
/// Example usage:
///
/// ```dart
/// final class MyAsyncHandler extends AsyncHandlerBase<String> {
///   MyAsyncHandler();
///
///   @override
///   Future<void> handle(String data) async {
///     await Future<void>.delayed(const Duration(milliseconds: 10));
///     print(data);
///   }
/// }
///
/// log.printer = MyAsyncHandler().publish;
/// ```
abstract base class AsyncHandlerBase<T extends Object?> {
  var _controller = StreamController<T>();

  /// Creates an [AsyncHandlerBase] with the specified processing handler.
  AsyncHandlerBase() {
    _listen();
  }

  void _listen() {
    _controller.stream.asyncMap(handle).listen((_) {});
  }

  /// The [handle] is called for each dispatched data. If it returns a
  /// [Future], subsequent data will wait in the internal queue until the
  /// [Future] completes, guaranteeing sequential data processing.
  FutureOr<void> handle(T data);

  /// Publishs a new [data] to be processed by the handler.
  ///
  /// The [data] is added to the internal queue and will be processed
  /// sequentially in the order it was published.
  void publish(T data) {
    if (_controller.isClosed) {
      throw StateError('The handler is closed');
    }

    _controller.add(data);
  }

  Future<void> flush() async {
    final oldController = _controller;
    _controller = StreamController<T>();
    await oldController.close();
    _listen();
  }

  /// Closes the internal stream controller.
  ///
  /// This method should be called when you want to stop processing data but
  /// for some reason cannot release the handler itself. (When the instance is
  /// released, all resources are disposed automatically.)
  Future<void> close() async {
    await _controller.close();
  }
}

/// A concrete implementation of [AsyncHandlerBase] that processes data
/// using a provided handler function.
///
/// Example usage:
///
/// ```dart
/// final asyncHandler = AsyncHandler<String>((data) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   print(data);
/// });
///
/// log.printer = asyncHandler.publish;
/// ```
final class AsyncHandler<T extends Object?> extends AsyncHandlerBase<T> {
  final FutureOr<void> Function(T data) _handler;

  /// Creates an [AsyncHandler] with the specified processing [handler].
  ///
  /// The [handler] is called for each dispatched data. If it returns a
  /// [Future], subsequent data will wait in the internal queue until the
  /// [Future] completes, guaranteeing sequential data processing.
  AsyncHandler(FutureOr<void> Function(T data) handler) : _handler = handler;

  @override
  FutureOr<void> handle(T data) => _handler(data);
}
