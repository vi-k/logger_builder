// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'dropped_reporter.dart';
import 'report.dart';

/// Internal engine shared by the two unbuffered asynchronous publishers:
/// a strictly serial queue, a flush that drains by re-subscribing, and a
/// terminal close.
///
/// The buffered half has had `BufferedPipeline` since 0.6.0. This is the
/// same move for the other half, which until now was the same hundred and
/// fifty lines written twice with `Log` replaced by `(Param, Log)` — and
/// that is not a tidiness complaint. It is the shape in which the flush
/// contract came to be right in one copy and wrong in the other, and in
/// which one copy's dartdoc lost a paragraph the other kept.
///
/// Not exported by the package.
final class AsyncPipeline<E> {
  final bool sync;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final void Function(E entry)? onDropped;
  final int? maxQueueSize;
  final FutureOr<void> Function(E entry) handle;

  StreamController<E> _controller;
  StreamSubscription<void>? _subscription;
  // Built on the first loss and only when the user left `onDropped` unset:
  // in a publisher that never drops anything it does not exist.
  DroppedReporter? _reporter;
  // Accepted and not yet handled, including the entry a paused `asyncMap`
  // is holding. Counted rather than measured: the entries sit inside the
  // StreamController, which shows neither its contents nor their number.
  int _pending = 0;
  Future<void>? _flushFuture;
  Future<void>? _closeFuture;
  // Captured at construction, not at first use. `_listen` also runs from
  // `flush`, and subscribing there would silently move every later
  // zone-reported handler error to whoever happened to flush last.
  final Zone _zone = Zone.current;

  AsyncPipeline({
    required this.handle,
    this.sync = false,
    this.onError,
    this.onDropped,
    this.maxQueueSize,
  }) : _controller = StreamController<E>(sync: sync) {
    _listen();
  }

  bool get isClosed => _closeFuture != null;

  void add(E entry) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    if (maxQueueSize case final limit? when _pending >= limit) {
      _reportDropped(entry);

      return;
    }

    _pending++;
    _controller.add(entry);
  }

  Future<void> flush() {
    // A close in progress is still draining, so "the queue is empty" is not
    // true yet: hand back the close instead of an already-completed future.
    if (_closeFuture case final closing?) {
      return closing;
    }

    final previous = _flushFuture;

    return _flushFuture = _flush(previous);
  }

  Future<void> _flush(Future<void>? previous) async {
    if (previous != null) {
      try {
        await previous;
      } on Object {
        // The previous flush already reported its failure to its caller.
      }
      // A close that started while this flush was queued is doing the
      // draining now, and waiting it out is what this flush promised.
      if (_closeFuture case final closing?) {
        await closing;

        return;
      }
    }

    final oldController = _controller;
    final oldSubscription = _subscription;
    _controller = StreamController<E>(sync: sync);
    await oldController.close();
    await oldSubscription?.cancel();
    _listen();
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    await _controller.close();
    await _subscription?.cancel();
    // After the drain: a loss during it still belongs to the count.
    _reporter?.flush();
  }

  void _listen() {
    _zone.run(() {
      _subscription = _controller.stream
          .asyncMap(_guardedHandle)
          .listen((_) {}, onError: _lastResortError);
    });
  }

  /// Last-resort guard for errors that escape [_guardedHandle] (they should
  /// not — errors are routed through [onError]).
  void _lastResortError(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }

  FutureOr<void> _guardedHandle(E entry) {
    try {
      final result = handle(entry);
      if (result is Future<void>) {
        return result.onError<Object>(_reportError).whenComplete(_finished);
      }
    } on Object catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }

    _finished();
  }

  /// One entry left the queue: handled, or handled by throwing.
  void _finished() => _pending--;

  void _reportDropped(E entry) {
    if (onDropped case final onDropped?) {
      // A throwing handler must not derail publishing.
      guarded(() => onDropped(entry));

      return;
    }

    // Nobody asked to see losses, which is not a reason to hide them.
    (_reporter ??= DroppedReporter()).record(1, DropCause.queueFull);
  }

  void _reportError(Object error, StackTrace stackTrace) =>
      reportTo(onError, error, stackTrace);
}
