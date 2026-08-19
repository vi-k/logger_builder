// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:collection';

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
  final int? maxQueueSize;

  /// The zone the *publisher* was built in, handed down rather than taken
  /// from `Zone.current` here.
  ///
  /// The queue is created lazily, on the first `publish`, so reading the
  /// current zone at this point would pin error reporting to whichever scope
  /// happened to log first — and a logger is built at the top level while
  /// the first log usually happens inside some request. The unbuffered
  /// engine pins its zone at construction and says so; this one used to do
  /// the opposite by accident.
  final Zone zone;

  final StreamController<void> _controller;
  StreamSubscription<void>? _subscription;
  // Accepted and not yet finished: what waits in `_entries` plus the batch
  // in flight, which is out of the list but still in memory.
  int _pending = 0;
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
    required this.zone,
    this.retryDelay = Duration.zero,
    this.maxRetries = 100,
    this.maxQueueSize,
  }) : _controller = StreamController<void>(sync: sync) {
    zone.run(() {
      _subscription = _controller.stream
          .asyncMap(_handleData)
          .listen(_next, onError: _lastResortError);
    });
  }

  bool get isClosed => _closing;

  void add(E entry) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    if (maxQueueSize case final limit? when _pending >= limit) {
      _reportDropped([entry]);

      return;
    }

    _pending++;
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
      _finishBatch(entries, retryBuffer);
      _reportError(error, stackTrace);
      return null;
    }

    if (result is Future<void>) {
      return result.onError<Object>(_reportError).whenComplete(() {
        _finishBatch(entries, retryBuffer);
      });
    }

    _finishBatch(entries, retryBuffer);

    return null;
  }

  void _finishBatch(List<E> entries, List<E> retryBuffer) {
    // `_isProcessing` is cleared in a `finally`, not at the end of the body.
    // No path here throws today — `_reportDropped` guards the callback and
    // the maps are identity-keyed, so a user `hashCode` never runs — but if
    // one ever did, the flag would stay up and every later `flush` and
    // `close` would wait on a completer nothing completes.
    try {
      _finish(entries, retryBuffer);
    } finally {
      _isProcessing = false;
    }
  }

  void _finish(List<E> entries, List<E> retryBuffer) {
    if (isClosed) {
      // Entries retried after close() would never be processed. Report them
      // rather than losing them without a trace.
      if (retryBuffer.isNotEmpty) {
        _reportDropped(List<E>.of(retryBuffer));
      }
      _pending -= entries.length;
    } else if (retryBuffer.isEmpty) {
      _retryAttempts = 0;
      _batchWasRetried = false;
      _pending -= entries.length;
    } else if (_retryAttempts >= maxRetries) {
      // Out of budget. Dropping is the lesser evil: a batch that fails
      // deterministically is never delivered by retrying either, it just
      // holds the queue, burns a core and keeps the isolate alive.
      _retryAttempts = 0;
      _batchWasRetried = false;
      _reportDropped(List<E>.of(retryBuffer));
      _pending -= entries.length;
    } else {
      _retryAttempts++;
      _batchWasRetried = true;
      final requeued = _inPublishOrder(entries, retryBuffer);
      _entries.insertAll(0, requeued);
      // The batch leaves the count except for what went back into the queue
      // — and a handler may hand back entries that never came from this
      // batch, which were never counted on the way in. Subtracting the
      // difference keeps the count on what is held rather than on what was
      // once accepted.
      _pending -= entries.length - requeued.length;
    }
  }

  /// [retryBuffer] rearranged to follow the order the entries were
  /// published in.
  ///
  /// Both halves of a formatter receive the buffer, so what comes back is
  /// "what `format` handed back" followed by "what `output` handed back".
  /// When they hand back different parts of the batch that is not publish
  /// order, and it went into the next batch exactly as it was found. Order
  /// is a promise this queue makes, and the recovery path is where breaking
  /// it is least likely to be noticed.
  List<E> _inPublishOrder(List<E> entries, List<E> retryBuffer) {
    if (retryBuffer.length < 2) {
      return retryBuffer;
    }

    // Counted and identity-keyed, like `_remainingLogs`: a batch may hold
    // the same entry twice, and a user `Log` may define value equality.
    final counts = HashMap<E, int>.identity();
    for (final entry in retryBuffer) {
      counts[entry] = (counts[entry] ?? 0) + 1;
    }

    final ordered = <E>[];
    for (final entry in entries) {
      final count = counts[entry] ?? 0;
      if (count > 0) {
        counts[entry] = count - 1;
        ordered.add(entry);
      }
    }

    if (ordered.length != retryBuffer.length) {
      // Anything the handler put in that did not come from this batch keeps
      // its own order, after the rest. Dropping it would be worse than
      // leaving it out of sequence.
      for (final entry in retryBuffer) {
        final count = counts[entry] ?? 0;
        if (count > 0) {
          counts[entry] = count - 1;
          ordered.add(entry);
        }
      }
    }

    return ordered;
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
