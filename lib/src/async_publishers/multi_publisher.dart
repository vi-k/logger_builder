import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';

/// A handler that delegates an event to multiple publishers simultaneously.
///
/// This class is useful when you want to route the same data (such as a log
/// event) to several different destinations, like a console printer, a file
/// writer, or a remote logging service, using a single overarching publisher.
///
/// Example usage:
///
/// ```dart
/// // The type argument is required on all three: a publisher stored in
/// // a local variable has no context type, so `Log` would be inferred as
/// // `CustomLog` and the assignment below would not compile.
/// final consolePrinter = CustomLogPublisher<Log>((log) => print('Console: $log'));
/// final filePrinter = AsyncPublisher<Log>((log) async {/* write to file */});
///
/// final multiPublisher = MultiPublisher<Log>([
///   consolePrinter,
///   filePrinter,
/// ]);
///
/// log.publisher = multiPublisher;
///
/// ...
///
/// await multiPublisher.flush();
/// ```
///
/// An exception thrown by one publisher does not interrupt publishing: the
/// remaining publishers still receive the log, and the error never propagates
/// to the logging call site. The caught error is passed to [onError] together
/// with the publisher that threw it. If [onError] is not set, the error is
/// reported to the current zone via [Zone.handleUncaughtError] — in Flutter it
/// ends up in `PlatformDispatcher.onError`, inside [runZonedGuarded] in its
/// handler. Note: in a plain Dart program without an error zone, an uncaught
/// asynchronous error terminates the isolate by default; in that case provide
/// [onError] or wrap the app in [runZonedGuarded].
base class MultiPublisher<Log extends CustomLog>
    implements CustomLogPublisher<Log>, Flushable, Closable {
  final List<CustomLogPublisher<Log>> _publishers;

  /// Called when one of the publishers throws from its `publish`, `flush`
  /// or `close`.
  ///
  /// Receives the failing publisher along with the error. When `null`,
  /// a `publish` error is reported to the current zone via
  /// [Zone.handleUncaughtError], while `flush`/`close` errors surface to the
  /// caller as a [ParallelWaitError].
  ///
  /// A throwing [onError] does not interrupt delivery: its own error is
  /// reported to the current zone.
  final void Function(
    CustomLogPublisher<Log> publisher,
    Object error,
    StackTrace stackTrace,
  )?
  onError;

  Future<void>? _closeFuture;

  /// Creates a publisher that forwards every log to all [publishers].
  ///
  /// The list is copied: later changes to the original list do not affect
  /// this publisher.
  MultiPublisher(List<CustomLogPublisher<Log>> publishers, {this.onError})
    : _publishers = List.of(publishers);

  /// Whether [close] has been called.
  bool get isClosed => _closeFuture != null;

  @override
  void publish(Log log) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    for (final publisher in _publishers) {
      try {
        publisher.publish(log);
      } on Object catch (error, stackTrace) {
        _reportError(publisher, error, stackTrace);
      }
    }
  }

  void _reportError(
    CustomLogPublisher<Log> publisher,
    Object error,
    StackTrace stackTrace,
  ) {
    if (onError case final onError?) {
      try {
        onError(publisher, error, stackTrace);
      } on Object catch (handlerError, handlerStackTrace) {
        // A throwing error handler must not interrupt delivery.
        Zone.current.handleUncaughtError(handlerError, handlerStackTrace);
      }
    } else {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Flushes every [Flushable] publisher in the list.
  ///
  /// With [onError] set, a throwing `flush` is reported there and this
  /// future completes normally; without it, the errors surface as
  /// a [ParallelWaitError] after all publishers have been flushed.
  ///
  /// After [close] this completes immediately without touching the wrapped
  /// publishers, matching the asynchronous publishers.
  @override
  Future<void> flush() =>
      isClosed
          ? Future<void>.value()
          : _waitAll<Flushable>((flushable) => flushable.flush());

  /// Closes every [Closable] publisher in the list and this publisher
  /// itself: afterwards [publish] throws a [StateError] and repeated calls
  /// return the same future.
  ///
  /// Errors are routed the same way as in [flush].
  @override
  Future<void> close() =>
      _closeFuture ??= _waitAll<Closable>((closable) => closable.close());

  /// Runs [action] for every publisher implementing [T] and awaits them all.
  Future<void> _waitAll<T>(Future<void> Function(T member) action) {
    if (onError == null) {
      return [
        for (final publisher in _publishers)
          if (publisher case final T member) Future.sync(() => action(member)),
      ].wait;
    }

    return [
      for (final publisher in _publishers)
        if (publisher case final T member)
          Future.sync(() => action(member)).onError<Object>(
            (error, stackTrace) => _reportError(publisher, error, stackTrace),
          ),
    ].wait;
  }
}
