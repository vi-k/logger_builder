import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';

/// An interface for publishers that can be flushed.
///
/// Flushing returns a future that completes when every log event accepted so
/// far (and, for buffered publishers, any events accepted while the flush is
/// in progress) has been processed.
abstract interface class Flushable {
  /// Completes when the publisher's queue has been fully processed.
  Future<void> flush();
}

/// The old name of [Flushable].
@Deprecated('Use Flushable instead')
typedef HasFlush = Flushable;

/// An interface for log-event handlers that can be closed.
///
/// Closing is terminal: after the returned future completes, the handler no
/// longer accepts log events.
abstract interface class Closable {
  /// Closes the handler after processing the already accepted log events.
  Future<void> close();
}

/// A base class for publishers that process log events asynchronously.
///
/// It provides common functionality for queuing incoming log events via a
/// stream and processing them sequentially, forming the foundation for
/// avoiding blocking operations during application execution.
///
/// > [!IMPORTANT]
/// > The queue is unbounded: if [handle] is slower than the rate of logging,
/// > pending events accumulate until the process runs out of memory. There
/// > is no overflow policy and no dropped-log counter — bound the input
/// > yourself if the destination can stall.
///
/// Example usage:
///
/// ```dart
/// final class FilePublisher extends AsyncPublisherBase<Log> {
///   @override
///   Future<void> handle(Log log) async {
///     // Perform asynchronous file write
///     await file.writeAsString(log.toString(), mode: FileMode.append);
///   }
/// }
/// ```
abstract base class AsyncPublisherBase<Log extends CustomLog>
    implements CustomLogPublisher<Log>, Flushable, Closable {
  /// Whether the underlying stream controller delivers events synchronously.
  final bool sync;

  /// Called when [handle] throws.
  ///
  /// When `null`, the error is reported to the current zone via
  /// [Zone.handleUncaughtError]. In either case the queue keeps processing
  /// subsequent log events.
  ///
  /// Note: in a plain Dart program without an error zone, an uncaught
  /// asynchronous error terminates the isolate by default — and then nothing
  /// keeps processing. Provide [onError] or wrap the app in
  /// [runZonedGuarded].
  final void Function(Object error, StackTrace stackTrace)? onError;

  StreamController<Log> _controller;
  StreamSubscription<void>? _subscription;
  Future<void>? _flushFuture;
  Future<void>? _closeFuture;
  final Zone _zone = Zone.current;

  /// Creates the publisher and starts its processing queue.
  AsyncPublisherBase({this.sync = false, this.onError})
    : _controller = StreamController<Log>(sync: sync) {
    _listen();
  }

  /// Processes a single log event.
  ///
  /// Events are processed strictly sequentially: the next event is not
  /// handled until the future returned by this method completes.
  FutureOr<void> handle(Log log);

  /// Whether [close] has been called.
  bool get isClosed => _closeFuture != null;

  @override
  void publish(Log log) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    _controller.add(log);
  }

  /// Completes when every log event queued before this call has been
  /// processed.
  ///
  /// Concurrent calls are serialized: a later flush first waits for the
  /// earlier one and then drains the events queued in between. The internal
  /// queue listener is re-created, but always in the zone this publisher was
  /// constructed in, so flushing does not move where later zone-reported
  /// handler errors land.
  ///
  /// Each call replaces the internal [StreamController] and its
  /// subscription, so flushing after every single log is measurably more
  /// expensive than letting the queue drain on its own.
  @override
  Future<void> flush() {
    if (isClosed) {
      return Future<void>.value();
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
      if (isClosed) {
        return;
      }
    }

    final oldController = _controller;
    final oldSubscription = _subscription;
    _controller = StreamController<Log>(sync: sync);
    await oldController.close();
    await oldSubscription?.cancel();
    _listen();
  }

  /// Closes the publisher after processing the already queued log events.
  ///
  /// After closing, [publish] throws a [StateError] and [flush] completes
  /// immediately. Repeated calls return the same future.
  ///
  /// Do not await this (or [flush]) from inside [handle]: closing waits for
  /// the running handler to complete, so it would deadlock.
  @override
  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    await _controller.close();
    await _subscription?.cancel();
  }

  void _listen() {
    // Always the construction zone. `_listen` also runs from `flush`, and
    // subscribing there would silently move every later zone-reported handler
    // error to whoever happened to flush last.
    _zone.run(() {
      _subscription = _controller.stream
          .asyncMap(_guardedHandle)
          .listen((_) {}, onError: _lastResortError);
    });
  }

  /// Last-resort guard for errors that escape [_guardedHandle]
  /// (they should not — errors are routed via the `onError` callback).
  void _lastResortError(Object error, StackTrace stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }

  FutureOr<void> _guardedHandle(Log log) {
    try {
      final result = handle(log);
      if (result is Future<void>) {
        return result.onError<Object>(_reportError);
      }
    } on Object catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }
  }

  void _reportError(Object error, StackTrace stackTrace) {
    if (onError case final onError?) {
      try {
        onError(error, stackTrace);
      } on Object catch (handlerError, handlerStackTrace) {
        // A throwing error handler must not break the queue.
        Zone.current.handleUncaughtError(handlerError, handlerStackTrace);
      }
    } else {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}

/// A publisher that processes log events asynchronously.
///
/// This publisher uses a stream to queue incoming log events and process them
/// sequentially. This is useful when the publishing action is computationally
/// expensive or involves asynchronous I/O (e.g., writing to a file, making
/// a network request), preventing the main application flow from blocking
/// or dropping logs.
///
/// Example usage:
///
/// ```dart
/// final asyncPublisher = AsyncPublisher<Log>((log) async {
///   await Future.delayed(Duration(milliseconds: 100)); // Simulate async work
///   print('Asynchronously processed: $log');
/// });
/// ```
final class AsyncPublisher<Log extends CustomLog>
    extends AsyncPublisherBase<Log> {
  /// The function that processes a single log event.
  final FutureOr<void> Function(Log log) handler;

  /// Creates a publisher backed by [handler].
  AsyncPublisher(this.handler, {super.sync, super.onError});

  @override
  FutureOr<void> handle(Log log) => handler(log);
}

/// An asynchronous publisher that applies format transformations onto a log
/// before directing it to an output destination.
///
/// Logs are first asynchronously transformed into an [Out] object, and then
/// passed to the actual output mechanism. Useful for serializing data or
/// preparing payloads for network calls.
///
/// Example usage:
///
/// ```dart
/// final asyncFormatter = AsyncFormatter<Log, Map<String, Object?>>(
///   format: (log) async {
///     // Asynchronously format the log
///     return {'level': log.levelName, 'message': log.message};
///   },
///   output: (out) async {
///     // Asynchronously output the formatted log
///     await apiClient.post('/logs', data: out);
///   },
/// );
/// ```
final class AsyncFormatter<Log extends CustomLog, Out extends Object?>
    extends AsyncPublisherBase<Log> {
  /// Transforms a log event into an [Out] object.
  final FutureOr<Out> Function(Log log) format;

  /// Receives the formatted [Out] object.
  final FutureOr<void> Function(Out out) output;

  /// Creates a publisher that formats logs via [format] and hands the
  /// result to [output].
  AsyncFormatter({
    required this.format,
    required this.output,
    super.sync,
    super.onError,
  });

  @override
  FutureOr<void> handle(Log log) => switch (format(log)) {
    final Future<Out> future => future.then(output),
    final Out out => output(out),
  };
}
