import 'dart:async';

import 'package:logger_builder/logger_builder.dart';

/// A handler that delegates an event to multiple publishers simultaneously.
///
/// This class is useful when you want to route the same data (such as a log
/// event) to several different destinations, like a console printer, a file
/// writer, or a remote logging service, using a single overarching publisher.
///
/// Example usage:
///
/// ```dart
/// final consolePrinter = CustomLogPublisher((log) => print('Console: $log'));
/// final filePrinter = AsyncPublisher((log) async {/* write to file */});
///
/// final multiPublisher = MultiPublisher([
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
    implements CustomLogPublisher<Log>, HasFlush {
  final List<CustomLogPublisher<Log>> _publishers;

  /// Called when one of the publishers throws from its `publish`.
  ///
  /// Receives the failing publisher along with the error. When `null`, the
  /// error is reported to the current zone via [Zone.handleUncaughtError].
  final void Function(
    CustomLogPublisher<Log> publisher,
    Object error,
    StackTrace stackTrace,
  )? onError;

  MultiPublisher(List<CustomLogPublisher<Log>> publishers, {this.onError})
      : _publishers = publishers;

  @override
  void publish(Log log) {
    for (final publisher in _publishers) {
      try {
        publisher.publish(log);
      } on Object catch (error, stackTrace) {
        if (onError case final onError?) {
          onError(publisher, error, stackTrace);
        } else {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      }
    }
  }

  @override
  Future<void> flush() =>
      _publishers.whereType<HasFlush>().map((e) => Future.sync(e.flush)).wait;
}
