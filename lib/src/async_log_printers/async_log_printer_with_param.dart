import 'dart:async';

base class AsyncLogPrinterWithParam<T extends Object?, P extends Object?> {
  final _controller = StreamController<(T, P)>(sync: true);

  final FutureOr<void> Function(T message, P param) _handler;

  AsyncLogPrinterWithParam(this._handler) {
    _controller.stream.asyncMap(_handleMessage).listen((_) {});
  }

  FutureOr<void> _handleMessage((T, P) e) => _handler(e.$1, e.$2);

  Future<void> dispose() async {
    await _controller.close();
  }

  void Function(T) publisher(P param) => (message) {
    _controller.add((message, param));
  };
}
