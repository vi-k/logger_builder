import 'dart:async';

/// An abstract base class for creating handlers that process data in batches
/// asynchronously.
///
/// This class buffers incoming data and processes them together using the
/// provided handler function. If the handler is currently processing a batch,
/// new data are queued in the buffer. Once the handler completes, it is
/// called again with the newly buffered data, ensuring sequential batch
/// processing.
///
/// The handler must return a list of unhandled data (or a `Future` completing
/// to it), which will be prepended to the buffer and retried in the next
/// batch. Returning an empty list indicates all data were successfully
/// processed.
///
/// Example usage:
///
/// ```dart
/// final class MyAsyncHandler extends AsyncBufferBase<String> {
///   MyAsyncHandler();
///
///   @override
///   Future<void> handle(List<String> buf) async {
///     await Future<void>.delayed(const Duration(milliseconds: 10));
///     print('Printing ${buf.length} messages...');
///     buf.forEach(print);
///     return []; // All data handled successfully
///   }
/// }
///
/// log.printer = MyAsyncHandler().publish;
/// ```
abstract base class AsyncBufferBase<T extends Object?> {
  final _controller = StreamController<void>();
  List<T> _buffer = [];
  Completer<void>? _flushCompleter;

  /// Creates an [AsyncBuffer] with the specified processing handler.
  AsyncBufferBase() {
    _controller.stream.asyncMap(_handleData).listen(_next);
  }

  /// Closes the internal stream controller.
  ///
  /// This method should be called when you want to stop processing data but
  /// for some reason cannot release the handler itself. (When the instance is
  /// released, all resources are disposed automatically.)
  Future<void> close() async {
    await _controller.close();
  }

  /// The [handle] is called with a list of buffered data. It must return
  /// a list of any data that could not be processed (e.g., due to a network
  /// error). These unhandled data will be inserted at the beginning of the
  /// buffer and retried when the next batch is processed.
  FutureOr<List<T>> handle(List<T> buf);

  /// Publishs a new [data] to be buffered and processed by the handler.
  ///
  /// The [data] is added to the internal buffer. If no batch is currently
  /// being processed, this triggers a new processing cycle.
  void publish(T data) {
    final isEmpty = _buffer.isEmpty;
    _buffer.add(data);
    if (isEmpty) {
      _controller.add(null);
    }
  }

  Future<void> flush() async {
    final completer = _flushCompleter ??= Completer<void>();
    return completer.future;
  }

  FutureOr<void> _handleData(void _) {
    final buffer = _buffer;
    _buffer = [];
    if (buffer.isNotEmpty) {
      switch (handle(buffer)) {
        case final Future<List<T>> future:
          return future.then(_handleUnhandled);
        case final unhandled:
          _handleUnhandled(unhandled);
      }
    }
  }

  void _next(void _) {
    if (_buffer.isNotEmpty) {
      _controller.add(null);
    } else {
      _flushCompleter?.complete();
      _flushCompleter = null;
    }
  }

  void _handleUnhandled(List<T> unhandled) {
    if (unhandled.isNotEmpty) {
      _buffer.insertAll(0, unhandled);
    }
  }
}

/// A concrete implementation of [AsyncBufferBase] that processes data
/// using a provided handler function.
///
/// Example usage:
///
/// ```dart
/// final asyncHandler = AsyncBuffer<String>((buf) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   for (final data in buf) {
///     print(data);
///   }
///   return [];
/// });
///
/// log.printer = asyncHandler.publish;
/// ```
final class AsyncBuffer<T extends Object?> extends AsyncBufferBase<T> {
  final FutureOr<List<T>> Function(List<T> buf) _handler;

  /// Creates an [AsyncBuffer] with the specified processing [handler].
  ///
  /// The handler is called with a list of buffered data. It must return
  /// a list of any data that could not be processed (e.g., due to a network
  /// error). These unhandled data will be inserted at the beginning of the
  /// buffer and retried when the next batch is processed.
  AsyncBuffer(FutureOr<List<T>> Function(List<T> buf) handler)
      : _handler = handler;

  @override
  FutureOr<List<T>> handle(List<T> buf) => _handler(buf);
}
