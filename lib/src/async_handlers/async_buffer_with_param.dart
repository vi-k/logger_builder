import 'dart:async';

import 'async_buffer.dart';

/// An abstract base class for creating handlers that process data in batches
/// asynchronously, and optionally accept a parameter.
///
/// Similar to [AsyncBuffer], this class buffers incoming data and processes
/// them in sequential batches. However, it allows attaching an additional
/// contextual parameter to publishers, which is then paired with each data in
/// the buffer.
///
/// The handler must return a list of unhandled data-parameter pairs (or a
/// `Future` completing to it), which will be prepended to the buffer and
/// retried in the next batch. Returning an empty list indicates all pairs were
/// successfully processed.
///
/// Example usage:
///
/// ```dart
/// final class MyAsyncHandler extends AsyncBufferWithParamBase<String, bool> {
///   MyAsyncHandler();
///
///   @override
///   Future<void> handle(List<(String, bool)> buf) async {
///     await Future<void>.delayed(const Duration(milliseconds: 10));
///     print('Printing ${buf.length} messages...');
///     for (final (data, isError) in entries) {
///       if (isError) {
///         print('Error: $data');
///       } else {
///         print(data);
///       }
///     }
///
///     return []; // All data handled successfully
///   }
/// }
///
/// log.printer = asyncHandler.publisher(false);
/// log[Levels.error].printer = asyncHandler.publisher(true);
/// ```
abstract base class AsyncBufferWithParamBase<T extends Object?,
    P extends Object?> {
  final _controller = StreamController<void>();
  List<(T, P)> _buffer = [];

  /// Creates an [AsyncBufferWithParam] with the specified processing handler.
  ///
  /// The handler is called with a list of buffered data and parameter
  /// pairs. It must return a list of any pairs that could not be processed
  /// (e.g., due to a network error). These unhandled pairs will be inserted at
  /// the beginning of the buffer and retried when the next batch is processed.
  AsyncBufferWithParamBase() {
    _controller.stream.asyncMap(_handleData).listen(_next);
  }

  /// The [handle] is called with a list of buffered data and parameter
  /// pairs. It must return a list of any pairs that could not be processed
  /// (e.g., due to a network error). These unhandled pairs will be inserted at
  /// the beginning of the buffer and retried when the next batch is processed.
  FutureOr<List<(T, P)>> handle(List<(T, P)> entries);

  FutureOr<void> _handleData(void _) {
    final buffer = _buffer;
    _buffer = [];
    if (buffer.isNotEmpty) {
      switch (handle(buffer)) {
        case final Future<List<(T, P)>> future:
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

  void _handleUnhandled(List<(T, P)> unhandled) {
    if (unhandled.isNotEmpty) {
      _buffer.insertAll(0, unhandled);
    }
  }

  /// Closes the internal stream controller.
  ///
  /// This method should be called when you want to stop processing data but
  /// for some reason cannot release the handler itself. (When the instance is
  /// released, all resources are disposed automatically.)
  Future<void> close() async {
    await _controller.close();
  }

  /// Adds a new [data] to be buffered and processed by the handler.
  ///
  /// The [data] is added to the internal buffer. If no batch is currently
  /// being processed, this triggers a new processing cycle.
  void add(T data, P param) {
    final isEmpty = _buffer.isEmpty;
    _buffer.add((data, param));
    if (isEmpty) {
      _controller.add(null);
    }
  }

  /// Creates a publisher function bound to a specific [param].
  ///
  /// The returned function takes an data, pairs it with the bound [param],
  /// and adds them to the internal buffer. If no batch is currently being
  /// processed, this triggers a new processing cycle.
  void Function(T) publisher(P param) => (data) {
        final isEmpty = _buffer.isEmpty;
        _buffer.add((data, param));
        if (isEmpty) {
          _controller.add(null);
        }
      };
}

/// A concrete implementation of [AsyncBufferWithParamBase] that processes
/// data using a provided handler function.
///
/// Example usage:
///
/// ```dart
/// final asyncHandler = AsyncBufferWithParam<String, int>((buf) async {
///   await Future<void>.delayed(const Duration(milliseconds: 10));
///   print('Printing ${buf.length} messages...');
///   for (final (data, param) in buf) {
///     print('$param: $data');
///   }
///   return []; // All entries handled successfully
/// });
///
/// log.printer = asyncHandler.publishWithParam(42);
/// ```
final class AsyncBufferWithParam<T extends Object?, P extends Object?>
    extends AsyncBufferWithParamBase<T, P> {
  final FutureOr<List<(T, P)>> Function(List<(T, P)> entries) _handler;

  /// Creates an [AsyncBufferWithParam] with the specified processing handler.
  ///
  /// The handler is called with a list of buffered data and parameter
  /// pairs. It must return a list of any pairs that could not be processed
  /// (e.g., due to a network error). These unhandled pairs will be inserted at
  /// the beginning of the buffer and retried when the next batch is processed.
  AsyncBufferWithParam(this._handler);

  @override
  FutureOr<List<(T, P)>> handle(List<(T, P)> entries) => _handler(entries);
}
