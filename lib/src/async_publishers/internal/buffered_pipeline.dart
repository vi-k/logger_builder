// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import 'dart:async';

/// Internal engine shared by the buffered async publishers: a tick-driven
/// batch queue with retry reinjection, drain-style flush, and error routing.
///
/// Not exported by the package.
final class BufferedPipeline<E> {
  final bool sync;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final FutureOr<void> Function(List<E> entries, List<E> retryBuffer) handle;

  final StreamController<void> _controller;
  StreamSubscription<void>? _subscription;
  List<E> _entries = [];
  Completer<void>? _flushCompleter;
  bool _isProcessing = false;
  Future<void>? _closeFuture;

  BufferedPipeline({
    required this.handle,
    this.sync = false,
    this.onError,
  }) : _controller = StreamController<void>(sync: sync) {
    _subscription = _controller.stream
        .asyncMap(_handleData)
        .listen(_next, onError: _lastResortError);
  }

  bool get isClosed => _closeFuture != null;

  void add(E entry) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    final wasEmpty = _entries.isEmpty;
    _entries.add(entry);
    if (wasEmpty && !_isProcessing) {
      _controller.add(null);
    }
  }

  Future<void> flush() {
    if (isClosed) {
      return Future<void>.value();
    }

    return _drain();
  }

  /// Closes the pipeline after draining every entry accepted so far,
  /// including entries added while a batch was in flight. Entries returned
  /// to the retry buffer after closing are dropped.
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    await _drain();
    await _controller.close();
    await _subscription?.cancel();
    _completeFlush();
  }

  Future<void> _drain() {
    if (_entries.isEmpty && !_isProcessing) {
      return Future<void>.value();
    }

    final completer = _flushCompleter ??= Completer<void>();
    return completer.future;
  }

  FutureOr<void> _handleData(void _) {
    final entries = _entries;
    if (entries.isEmpty) {
      return null;
    }

    _entries = [];
    _isProcessing = true;
    final retryBuffer = <E>[];

    final FutureOr<void> result;
    try {
      result = handle(entries, retryBuffer);
    } on Object catch (error, stackTrace) {
      // Finish the batch BEFORE reporting, so nothing can skip the cleanup.
      _finishBatch(retryBuffer);
      _reportError(error, stackTrace);
      return null;
    }

    if (result is Future<void>) {
      return result.onError<Object>(_reportError).whenComplete(() {
        _finishBatch(retryBuffer);
      });
    }

    _finishBatch(retryBuffer);
    return null;
  }

  void _finishBatch(List<E> retryBuffer) {
    // Entries retried after close() would never be processed — drop them.
    if (!isClosed) {
      _entries.insertAll(0, retryBuffer);
    }
    _isProcessing = false;
  }

  void _next(void _) {
    if (!_controller.isClosed && _entries.isNotEmpty) {
      _controller.add(null);
    } else {
      _completeFlush();
    }
  }

  void _completeFlush() {
    _flushCompleter?.complete();
    _flushCompleter = null;
  }

  void _reportError(Object error, StackTrace stackTrace) {
    if (onError case final onError?) {
      try {
        onError(error, stackTrace);
      } on Object catch (handlerError, handlerStackTrace) {
        // A throwing error handler must not wedge the pipeline.
        Zone.current.handleUncaughtError(handlerError, handlerStackTrace);
      }
    } else {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Last-resort guard: keeps the tick loop alive if an error ever escapes
  /// [_handleData] (it should not — errors are routed via [_reportError]).
  void _lastResortError(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
    _next(null);
  }
}
