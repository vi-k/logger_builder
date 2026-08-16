import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';

/// A publisher that transforms every log before handing it to the wrapped
/// publisher.
///
/// Use it to apply a different [LogTransformer] per destination — e.g.
/// mask secrets only in the file/network publisher while the console one
/// stays verbatim:
///
/// ```dart
/// logger.publisher = MultiPublisher([
///   consolePrinter,
///   TransformPublisher(fileStorage, transformer: redact),
/// ]);
/// ```
///
/// The transformer returning `null` drops the log. A throwing transformer
/// also drops the log (fail-closed: the untransformed log is never
/// published) and reports the error to [onError]; without [onError] the
/// error goes to the current zone via [Zone.handleUncaughtError].
///
/// [flush] and [close] are delegated to the wrapped publisher when it
/// implements [Flushable]/[Closable], and complete immediately otherwise.
///
/// > [!WARNING]
/// > Never log into a logger that publishes through this publisher from
/// > inside the [transformer]: the nested call comes back here, re-enters
/// > the transformer and recurses until the stack is exhausted. The
/// > resulting [StackOverflowError] is reported once via [onError], but
/// > every unwinding frame still publishes its own log — a single logging
/// > call becomes thousands of published duplicates.
final class TransformPublisher<Log extends CustomLog>
    implements CustomLogPublisher<Log>, Flushable, Closable {
  final CustomLogPublisher<Log> _inner;

  /// Transforms a log before publishing; `null` drops the log.
  final LogTransformer<Log> transformer;

  /// Called when [transformer] throws.
  ///
  /// When `null`, the error is reported to the current zone via
  /// [Zone.handleUncaughtError]. A throwing [onError] does not interrupt
  /// delivery: its own error is reported to the current zone.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Creates a publisher that transforms every log before [inner].
  TransformPublisher(
    CustomLogPublisher<Log> inner, {
    required this.transformer,
    this.onError,
  }) : _inner = inner;

  @override
  void publish(Log log) {
    final Log? transformed;
    try {
      transformed = transformer(log);
    } on Object catch (error, stackTrace) {
      _reportError(error, stackTrace);

      return;
    }

    if (transformed != null) {
      _inner.publish(transformed);
    }
  }

  void _reportError(Object error, StackTrace stackTrace) {
    if (onError case final onError?) {
      try {
        onError(error, stackTrace);
      } on Object catch (handlerError, handlerStackTrace) {
        // A throwing error handler must not interrupt delivery.
        Zone.current.handleUncaughtError(handlerError, handlerStackTrace);
      }
    } else {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  @override
  Future<void> flush() => switch (_inner) {
        final Flushable flushable => flushable.flush(),
        _ => Future.value(),
      };

  @override
  Future<void> close() => switch (_inner) {
        final Closable closable => closable.close(),
        _ => Future.value(),
      };
}
