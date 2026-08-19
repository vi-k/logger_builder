// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'report.dart';

/// Internal engine shared by the buffered async publishers: a tick-driven
/// batch queue with retry reinjection, drain-style flush, and error routing.
///
/// Not exported by the package.
final class BufferedPipeline<E> {
  final bool sync;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final void Function(List<E> entries)? onDropped;
  final FutureOr<void> Function(List<E> entries, List<E> retryBuffer) handle;
  final Duration retryDelay;
  final int maxRetries;

  final StreamController<void> _controller;
  StreamSubscription<void>? _subscription;
  List<E> _entries = [];
  Completer<void>? _flushCompleter;
  Timer? _retryTimer;
  bool _isProcessing = false;
  bool _batchWasRetried = false;
  // Counts a run of failures, not the lifetime of the pipeline: a batch
  // that gets through pays the whole budget back.
  int _retryAttempts = 0;
  // Raised before `close()` runs any code, so a batch finishing during the
  // shutdown already sees the pipeline as closed. Deriving `isClosed` from
  // `_closeFuture` instead left a synchronous window in which retried
  // entries were re-queued and armed yet another retry timer.
  bool _closing = false;
  Future<void>? _closeFuture;

  BufferedPipeline({
    required this.handle,
    this.sync = false,
    this.onError,
    this.onDropped,
    this.retryDelay = Duration.zero,
    this.maxRetries = 100,
  }) : _controller = StreamController<void>(sync: sync) {
    _subscription = _controller.stream
        .asyncMap(_handleData)
        .listen(_next, onError: _lastResortError);
  }

  bool get isClosed => _closing;

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
    // A close in progress is still draining, so "the queue is empty" is not
    // true yet: hand back the close instead of an already-completed future,
    // which would tell the caller everything is out while it is still in
    // flight. (The `_drain` fallback covers only the synchronous prefix of
    // `_close`, before `_closeFuture` has been assigned.)
    if (_closing) {
      return _closeFuture ?? _drain();
    }

    return _drain();
  }

  /// Closes the pipeline after draining every entry accepted so far,
  /// including entries added while a batch was in flight. Entries returned
  /// to the retry buffer after closing are dropped, and reported to
  /// [onDropped].
  Future<void> close() {
    if (_closeFuture case final closing?) {
      return closing;
    }

    _closing = true;

    return _closeFuture = _close();
  }

  Future<void> _close() async {
    // A pending retry timer would hold the drain for its whole delay, and the
    // entries waiting on it are dropped afterwards anyway. Cancel it and make
    // one prompt final attempt instead of sleeping through the shutdown.
    if (_retryTimer case final timer?) {
      _retryTimer = null;
      timer.cancel();
      _tick();
    }

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
    if (isClosed) {
      // Entries retried after close() would never be processed. Report them
      // rather than losing them without a trace.
      if (retryBuffer.isNotEmpty) {
        _reportDropped(List<E>.of(retryBuffer));
      }
    } else if (retryBuffer.isEmpty) {
      _retryAttempts = 0;
      _batchWasRetried = false;
    } else if (_retryAttempts >= maxRetries) {
      // Out of budget. Dropping is the lesser evil: a batch that fails
      // deterministically is never delivered by retrying either, it just
      // holds the queue, burns a core and keeps the isolate alive.
      _retryAttempts = 0;
      _batchWasRetried = false;
      _reportDropped(List<E>.of(retryBuffer));
    } else {
      _retryAttempts++;
      _batchWasRetried = true;
      _entries.insertAll(0, retryBuffer);
    }
    _isProcessing = false;
  }

  void _next(void _) {
    if (_controller.isClosed || _entries.isEmpty) {
      _completeFlush();

      return;
    }

    if (_batchWasRetried) {
      _batchWasRetried = false;
      // A batch that handed entries back made no progress. Re-ticking through
      // the microtask queue would spin without ever yielding: while the sink
      // stays unavailable, timers, I/O and even the application's own close()
      // call would never get a turn. Going through the event loop keeps the
      // isolate responsive and lets close() stop the retries; retryDelay
      // additionally spaces the attempts out. The timer is kept so close()
      // can cancel it instead of waiting out the delay.
      _retryTimer = Timer(_backoff(), _tick);

      return;
    }

    _controller.add(null);
  }

  /// [retryDelay], doubled once per attempt already made and capped at 32
  /// times the base.
  ///
  /// A flat delay spends the whole budget in the first fraction of a second,
  /// which is no use against the case the delay exists for — a sink that is
  /// down for a while. Zero stays zero: there is nothing to space out, and
  /// the attempt count is what bounds the loop.
  Duration _backoff() {
    if (retryDelay == Duration.zero) {
      return Duration.zero;
    }

    final doublings = (_retryAttempts - 1).clamp(0, 5);

    return retryDelay * (1 << doublings);
  }

  void _tick() {
    _retryTimer = null;
    if (_controller.isClosed || _entries.isEmpty) {
      _completeFlush();

      return;
    }

    _controller.add(null);
  }

  void _completeFlush() {
    _flushCompleter?.complete();
    _flushCompleter = null;
  }

  void _reportDropped(List<E> dropped) {
    if (onDropped case final onDropped?) {
      // A throwing handler must not derail the shutdown.
      guarded(() => onDropped(dropped));
    }
  }

  void _reportError(Object error, StackTrace stackTrace) =>
      reportTo(onError, error, stackTrace);

  /// Last-resort guard: keeps the tick loop alive if an error ever escapes
  /// [_handleData] (it should not — errors are routed via [_reportError]).
  void _lastResortError(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
    _next(null);
  }
}
