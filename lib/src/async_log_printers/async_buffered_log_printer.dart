import 'dart:async';

base class AsyncBufferedLogPrinter<T extends Object?> {
  final _controller = StreamController<void>();
  List<T> _buffer = [];

  final FutureOr<List<T>> Function(List<T> messages) _handler;

  AsyncBufferedLogPrinter(this._handler) {
    _controller.stream.asyncMap(_handleMessages).listen(_next);
  }

  FutureOr<void> _handleMessages(_) {
    final buffer = _buffer;
    _buffer = [];
    if (buffer.isNotEmpty) {
      switch (_handler(buffer)) {
        case final Future<List<T>> future:
          return future.then(_handleUnhandled);
        case final unhandled:
          _handleUnhandled(unhandled);
      }
    }
  }

  void _next(_) {
    if (_buffer.isNotEmpty) {
      _controller.add(null);
    }
  }

  void _handleUnhandled(List<T> unhandled) {
    if (unhandled.isNotEmpty) {
      _buffer.insertAll(0, unhandled);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  void publisher(T message) {
    final isEmpty = _buffer.isEmpty;
    _buffer.add(message);
    if (isEmpty) {
      _controller.add(null);
    }
  }
}
