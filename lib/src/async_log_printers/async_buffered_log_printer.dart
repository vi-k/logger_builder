import 'dart:async';

/// A base class for creating log printers that process messages in batches
/// asynchronously.
///
/// This class buffers incoming log messages and processes them together using
/// the provided handler function. If the handler is currently processing
/// a batch, new messages are queued in the buffer. Once the handler completes,
/// it is called again with the newly buffered messages, ensuring sequential
/// batch processing.
///
/// The handler must return a list of unhandled messages (or a `Future`
/// completing to it), which will be prepended to the buffer and retried in the
/// next batch. Returning an empty list indicates all messages were
/// successfully processed.
///
/// Example usage:
///
/// ```dart
/// final asyncPrinter = AsyncBufferedLogPrinter<String>((messages) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   print('Sending ${messages.length} messages...');
///   messages.forEach(print);
///   return []; // All messages handled successfully
/// });
///
/// log.printer = asyncPrinter.publisher;
/// ```
base class AsyncBufferedLogPrinter<T extends Object?> {
  final _controller = StreamController<void>();
  List<T> _buffer = [];

  final FutureOr<List<T>> Function(List<T> messages) _handler;

  /// Creates an [AsyncBufferedLogPrinter] with the specified processing
  /// handler.
  ///
  /// The handler is called with a list of buffered log messages. It must
  /// return a list of any messages that could not be processed (e.g., due to
  /// a network error). These unhandled messages will be inserted at the
  /// beginning of the buffer and retried when the next batch is processed.
  AsyncBufferedLogPrinter(this._handler) {
    _controller.stream.asyncMap(_handleMessages).listen(_next);
  }

  FutureOr<void> _handleMessages(void _) {
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

  void _next(void _) {
    if (_buffer.isNotEmpty) {
      _controller.add(null);
    }
  }

  void _handleUnhandled(List<T> unhandled) {
    if (unhandled.isNotEmpty) {
      _buffer.insertAll(0, unhandled);
    }
  }

  /// Closes the internal stream controller and releases resources.
  ///
  /// This method should be called when the printer is no longer needed
  /// to prevent memory leaks and ensure that the stream is properly closed.
  Future<void> dispose() async {
    await _controller.close();
  }

  /// Publishes a new log [message] to be buffered and processed by the
  /// handler.
  ///
  /// The [message] is added to the internal buffer. If no batch is currently
  /// being processed, this triggers a new processing cycle. This method is
  /// typically assigned to a Logger instance's printer callback.
  void publisher(T message) {
    final isEmpty = _buffer.isEmpty;
    _buffer.add(message);
    if (isEmpty) {
      _controller.add(null);
    }
  }
}
