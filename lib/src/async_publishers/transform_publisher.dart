import 'dart:async';

import '../custom_logger/custom_log.dart';
import '../custom_logger/custom_log_publisher.dart';
import 'async_publisher.dart';
import 'internal/report.dart';

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
/// A throwing wrapped publisher goes to [onError] too. Without one it
/// keeps travelling to the logging call site, unchanged from an
/// unwrapped publisher — this class does not quietly swallow what it
/// wraps.
///
/// [flush] and [close] are delegated to the wrapped publisher when it
/// implements [Flushable]/[Closable], and complete immediately otherwise.
/// [close] is terminal and idempotent regardless of what the wrapped
/// publisher is: afterwards [publish] throws a [StateError] and repeated
/// calls return the same future.
///
/// > [!WARNING]
/// > The [transformer] must not log into a logger that publishes through
/// > this publisher: the nested call would come back here, re-enter the
/// > transformer and recurse until the stack is exhausted. Such a call is
/// > detected — the nested log is dropped and a [StateError] goes to
/// > [onError] (or to the current zone). Chained transform publishers are
/// > not affected: the guard is released before the log is handed on.
/// >
/// > The guard is synchronous. A nested log deferred with `scheduleMicrotask`,
/// > a `Future` or an `await` runs after it has been released, and so does the
/// > `handle` of an asynchronous publisher wrapped by this one — neither is
/// > guarded, and an unconditional cycle through either loops forever.
final class TransformPublisher<Log extends CustomLog>
    implements CustomLogPublisher<Log>, Flushable, Closable {
  final CustomLogPublisher<Log> _inner;

  /// Transforms a log before publishing; `null` drops the log.
  final LogTransformer<Log> transformer;

  /// Called when [transformer] throws, and when the wrapped publisher
  /// throws from its `publish`.
  ///
  /// The two cases differ in what happens without a handler. A throwing
  /// [transformer] is reported to the current zone via
  /// [Zone.handleUncaughtError]; a throwing wrapped publisher keeps
  /// travelling to the logging call site, which is where an unhandled
  /// publisher error has always surfaced. A throwing [onError] does not
  /// interrupt delivery: its own error is reported to the current zone.
  final void Function(Object error, StackTrace stackTrace)? onError;

  bool _transforming = false;
  Future<void>? _closeFuture;

  /// Creates a publisher that transforms every log before [inner].
  TransformPublisher(
    CustomLogPublisher<Log> inner, {
    required this.transformer,
    this.onError,
  }) : _inner = inner;

  /// Whether [close] has been called.
  bool get isClosed => _closeFuture != null;

  @override
  void publish(Log log) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    if (_transforming) {
      _reportError(
        StateError(
          'A log transformer must not log into its own publisher; '
          'the nested log was dropped',
        ),
        StackTrace.current,
      );

      return;
    }

    final Log? transformed;
    _transforming = true;
    try {
      transformed = transformer(log);
    } on Object catch (error, stackTrace) {
      _reportError(error, stackTrace);

      return;
    } finally {
      // Scoped to this publisher's own transformer. A chained
      // TransformPublisher keeps its own flag, on its own object, so the
      // release point does not affect it either way.
      _transforming = false;
    }

    if (transformed != null) {
      try {
        _inner.publish(transformed);
      } on Object catch (error, stackTrace) {
        // The same rule as `CustomLevelLogger.publishLog`: with a handler
        // the error is reported, without one it keeps travelling to the
        // logging call site. Outside the `try` altogether, as it used to
        // be, a handler set on this publisher was simply ignored for the
        // half of the work that is most likely to fail.
        if (onError == null) {
          rethrow;
        }
        _reportError(error, stackTrace);
      }
    }
  }

  void _reportError(Object error, StackTrace stackTrace) =>
      reportTo(onError, error, stackTrace);

  /// Delegated to the wrapped publisher, or completed at once when it is
  /// not [Flushable].
  ///
  /// While a [close] is draining this returns that same future rather than
  /// an already-completed one, as every publisher does: the close is what
  /// is still emptying the wrapped queue.
  @override
  Future<void> flush() {
    if (_closeFuture case final closing?) {
      return closing;
    }

    return switch (_inner) {
      final Flushable flushable => flushable.flush(),
      _ => Future.value(),
    };
  }

  @override
  Future<void> close() => _closeFuture ??= Future.sync(
        () => switch (_inner) {
          final Closable closable => closable.close(),
          _ => Future.value(),
        },
      );
}
