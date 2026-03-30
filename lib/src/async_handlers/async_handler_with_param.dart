import 'dart:async';

import 'async_handler.dart';

/// An abstrart base class for creating handlers that perform asynchronous
/// operations and accept a parameter.
///
/// Similar to [AsyncHandler], this class ensures that asynchronous operations
/// are processed sequentially. It allows attaching an additional contextual
/// param to publishers, which is then passed alongside the data to the
/// processing [handle] method.
///
/// Example usage:
///
/// ```dart
/// final class MyAsyncHandler extends AsyncHandlerWithParamBase<String, bool> {
///   MyAsyncHandler();
///
///   @override
///   Future<void> handler(String data, bool isError) async {
///     await Future<void>.delayed(const Duration(milliseconds: 10));
///     if (isError) {
///       print('Error: $data');
///     } else {
///       print(data);
///     }
///   }
/// }
///
/// final myHandler = AsyncHandlerWithParam<String, bool>();
/// log.printer = myHandler.publishWithParam(false);
/// log[Levels.error].printer = myHandler.publishWithParam(true);
/// ```
abstract base class AsyncHandlerWithParamBase<T extends Object?,
    P extends Object?> {
  var _controller = StreamController<(T, P)>();

  /// Creates an [AsyncHandlerWithParamBase] with the specified processing
  /// handler.
  AsyncHandlerWithParamBase() {
    _listen();
  }

  void _listen() {
    _controller.stream.asyncMap(_handleData).listen((_) {});
  }

  /// The [handle] is called for each dispatched data. If it returns a
  /// [Future], subsequent data will wait in the internal queue until the
  /// [Future] completes, guaranteeing sequential data processing.
  FutureOr<void> handle(T data, P param);

  FutureOr<void> _handleData((T, P) e) => handle(e.$1, e.$2);

  /// Closes the internal stream controller.
  ///
  /// This method should be called when you want to stop processing data but
  /// for some reason cannot release the handler itself. (When the instance is
  /// released, all resources are disposed automatically.)
  Future<void> close() async {
    await _controller.close();
  }

  /// Publishs a new [data] to be processed by the handler.
  ///
  /// The [data] is added to the internal queue and will be processed
  /// sequentially in the order it was published.
  void publish(T data, P param) {
    if (_controller.isClosed) {
      throw StateError('The handler is closed');
    }

    _controller.add((data, param));
  }

  /// Creates a publisher function bound to a specific [param].
  ///
  /// The returned function takes an data, pairs it with the bound [param],
  /// and adds them to the internal queue for sequential processing.
  void Function(T) publishWithParam(P param) => (data) {
        publish(data, param);
      };

  Future<void> flush() async {
    final oldController = _controller;
    _controller = StreamController<(T, P)>();
    await oldController.close();
    _listen();
  }
}

/// A concrete implementation of [AsyncHandlerWithParamBase] that processes
/// data using a provided handler function.
///
/// Example usage:
///
/// ```dart
/// final asyncHandler = AsyncHandlerWithParam<String, int>((data, param) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   print('$param: $data');
/// });
///
/// log.printer = asyncHandler.publishWithParam(42);
/// ```
final class AsyncHandlerWithParam<T extends Object?, P extends Object?>
    extends AsyncHandlerWithParamBase<T, P> {
  final FutureOr<void> Function(T data, P param) _handler;

  /// Creates an [AsyncHandlerWithParam] with the specified processing handler.
  ///
  /// The handler is called with both the dispatched data and the param
  /// supplied when its specific publisher was created. If it returns
  /// a [Future], subsequent data will wait in the internal queue until the
  /// [Future] completes, guaranteeing sequential data processing.
  AsyncHandlerWithParam(this._handler);

  @override
  FutureOr<void> handle(T data, P param) => _handler(data, param);
}
