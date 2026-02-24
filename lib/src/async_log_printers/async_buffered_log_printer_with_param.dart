import 'dart:async';

import 'async_buffered_log_printer.dart';

/// A base class for creating log printers that process messages in batches
/// asynchronously, and optionally accept a parameter.
///
/// Similar to [AsyncBufferedLogPrinter], this class buffers incoming log
/// messages and processes them in sequential batches. However, it allows
/// attaching an additional contextual parameter to publishers, which is then
/// paired with each log message in the buffer.
///
/// The handler must return a list of unhandled message-parameter pairs (or a
/// `Future` completing to it), which will be prepended to the buffer and
/// retried in the next batch. Returning an empty list indicates all pairs were
/// successfully processed.
///
/// Example usage:
///
/// ```dart
/// final asyncPrinter = AsyncBufferedLogPrinterWithParam<String, bool>((entries) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   print('Sending ${entries.length} messages...');
///   for (final (message, isError) in entries) {
///     if (isError) {
///       print('Error: $message');
///     } else {
///       print(message);
///     }
///   }
///   return []; // All entries handled successfully
/// });
///
/// log.printer = asyncPrinter.publisher(false);
/// log[Levels.error].printer = asyncPrinter.publisher(true);
/// ```
base class AsyncBufferedLogPrinterWithParam<
  T extends Object?,
  P extends Object?
> {
  final _controller = StreamController<void>();
  List<(T, P)> _buffer = [];

  final FutureOr<List<(T, P)>> Function(List<(T, P)> entries) _handler;

  /// Creates an [AsyncBufferedLogPrinterWithParam] with the specified
  /// processing handler.
  ///
  /// The handler is called with a list of buffered log message and parameter
  /// pairs. It must return a list of any pairs that could not be processed
  /// (e.g., due to a network error). These unhandled pairs will be inserted at
  /// the beginning of the buffer and retried when the next batch is processed.
  AsyncBufferedLogPrinterWithParam(this._handler) {
    _controller.stream.asyncMap(_handleMessages).listen(_next);
  }

  FutureOr<void> _handleMessages(_) {
    final buffer = _buffer;
    _buffer = [];
    if (buffer.isNotEmpty) {
      switch (_handler(buffer)) {
        case final Future<List<(T, P)>> future:
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

  void _handleUnhandled(List<(T, P)> unhandled) {
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

  /// Creates a publisher function bound to a specific [param].
  ///
  /// The returned function takes a log message, pairs it with the bound
  /// [param], and adds them to the internal buffer. If no batch is currently
  /// being processed, this triggers a new processing cycle. This created
  /// publisher is typically assigned to a Logger instance's printer callback
  /// or used with log-level specific printers.
  void Function(T) publisher(P param) => (message) {
    final isEmpty = _buffer.isEmpty;
    _buffer.add((message, param));
    if (isEmpty) {
      _controller.add(null);
    }
  };
}
