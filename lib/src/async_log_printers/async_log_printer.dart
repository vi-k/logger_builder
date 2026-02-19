import 'dart:async';

base class AsyncLogPrinter<T extends Object?> {
  final _controller = StreamController<T>(sync: true);

  final FutureOr<void> Function(T message) _handler;

  AsyncLogPrinter(this._handler) {
    _controller.stream.asyncMap(_handler).listen((_) {});
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  void publisher(T message) {
    _controller.add(message);
  }
}
