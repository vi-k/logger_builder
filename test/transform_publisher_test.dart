import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/matchers.dart';

final class _LifecyclePublisher
    implements CustomLogPublisher<Log>, Flushable, Closable {
  final published = <Log>[];
  int flushCount = 0;
  int closeCount = 0;

  @override
  void publish(Log log) => published.add(log);

  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  Future<void> close() async {
    closeCount++;
  }
}

/// An inner publisher whose `close()` throws before its first `await`.
/// That is the shape any `Future<void> close()` written without `async`
/// takes when it checks its state up front: the error arrives synchronously,
/// not as a failed future.
final class _SyncThrowingClosePublisher
    implements CustomLogPublisher<Log>, Closable, Flushable {
  final published = <Log>[];
  int closeCount = 0;

  @override
  void publish(Log log) => published.add(log);

  @override
  Future<void> flush() => throw StateError('inner flush failed');

  @override
  Future<void> close() {
    closeCount++;

    throw StateError('inner close failed');
  }
}

void main() {
  group('TransformPublisher', () {
    late List<Log> published;
    late Logger logger;

    void setUpLogger(CustomLogPublisher<Log> publisher) {
      published = <Log>[];
      logger = Logger('test')
        ..level = Levels.all
        ..publisher = publisher;
    }

    test('inner receives the transformed log', () {
      setUpLogger(
        TransformPublisher(
          CustomLogPublisher((log) => published.add(log)),
          transformer: (log) => Log.copy(log, message: '***'),
        ),
      );

      logger.i('secret');

      expect(published, hasLength(1));
      expect(published.single.message, '***');
    });

    test('null from transformer drops the log', () {
      setUpLogger(
        TransformPublisher(
          CustomLogPublisher((log) => published.add(log)),
          transformer: (log) => null,
        ),
      );

      logger.i('secret');

      expect(published, isEmpty);
    });

    test('throwing transformer drops the log and reports to the zone', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          setUpLogger(
            TransformPublisher(
              CustomLogPublisher((log) => published.add(log)),
              transformer: (log) => throw StateError('bad transformer'),
            ),
          );

          logger.i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published, isEmpty);
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });

    test('throwing transformer reports to onError instead of the zone', () {
      final errors = <Object>[];
      final zoneErrors = <Object>[];
      runZonedGuarded(
        () {
          setUpLogger(
            TransformPublisher(
              CustomLogPublisher((log) => published.add(log)),
              transformer: (log) => throw StateError('bad transformer'),
              onError: (error, stackTrace) => errors.add(error),
            ),
          );

          logger.i('secret');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(published, isEmpty);
      expect(errors, hasLength(1));
      expect(zoneErrors, isEmpty);
    });

    test('throwing onError is reported to the zone, delivery continues', () {
      final zoneErrors = <Object>[];
      runZonedGuarded(
        () {
          setUpLogger(
            TransformPublisher(
              CustomLogPublisher((log) => published.add(log)),
              transformer: (log) => log.message == 'boom'
                  ? throw StateError('bad transformer')
                  : log,
              onError: (error, stackTrace) => throw StateError('bad handler'),
            ),
          );

          logger
            ..i('boom')
            ..i('fine');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors, hasLength(1));
      expect(published, hasLength(1));
      expect(published.single.message, 'fine');
    });

    // Regression: M4 (project review 2026-08-19[2]) — `_inner.publish` sat
    // outside the try, so a throwing sink behind a TransformPublisher took
    // the route of an unhandled publisher error even when this publisher
    // had a handler of its own. `MultiPublisher` catches the same throw and
    // routes it to its `onError`; the two wrappers disagreed.
    test('a throwing inner publisher reports to onError', () {
      final errors = <Object>[];
      setUpLogger(
        TransformPublisher(
          CustomLogPublisher<Log>((log) => throw StateError('sink down')),
          transformer: (log) => log,
          onError: (error, stackTrace) => errors.add(error),
        ),
      );

      expect(() => logger.i('hello'), returnsNormally);
      expect(errors.single, isA<StateError>());
    });

    // Regression: M4 — the default is deliberately left alone. Without a
    // handler a throwing publisher reaches the logging call site, and that
    // is the package-wide rule (`CustomLevelLogger.publishLog`); this
    // publisher is not special enough to opt out of it.
    test('without onError a throwing inner publisher reaches the call site',
        () {
      setUpLogger(
        TransformPublisher(
          CustomLogPublisher<Log>((log) => throw StateError('sink down')),
          transformer: (log) => log,
        ),
      );

      expect(() => logger.i('hello'), throwsStateError);
    });

    test('a reentrant transformer drops the nested log', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          setUpLogger(
            TransformPublisher(
              CustomLogPublisher((log) => published.add(log)),
              transformer: (log) {
                logger.i('from inside the transformer');

                return Log.copy(log, message: '***');
              },
              onError: (error, stackTrace) => errors.add(error),
            ),
          );

          logger.i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, '***');
      expect(errors.single, isA<StateError>());
    });

    // Regression: M17 (project review 2026-08-19[2]) — the guard above was
    // never executed by any test. The existing reentrancy test logs into
    // the *same* level, where the level logger's own guard fires first, so
    // deleting this one left the suite green. Logging into a different
    // level of the same logger is the case that reaches it.
    test('a transformer logging into another level trips this guard', () {
      final published = <Log>[];
      final errors = <Object>[];
      late final Logger logger;

      final publisher = TransformPublisher<Log>(
        CustomLogPublisher<Log>(published.add),
        transformer: (log) {
          if (log.message == 'outer') {
            logger.e('nested');
          }

          return log;
        },
        onError: (error, stackTrace) => errors.add(error),
      );
      logger = Logger('test')
        ..level = Levels.all
        ..publisher = publisher;

      logger.i('outer');

      expect(
        published.map((log) => log.message),
        ['outer'],
        reason: 'the nested log must be dropped, not published',
      );
      expect(errors.single, isA<StateError>());
    });

    test('chained transform publishers do not trip the guard', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          setUpLogger(
            TransformPublisher(
              TransformPublisher(
                CustomLogPublisher((log) => published.add(log)),
                transformer: (log) =>
                    Log.copy(log, message: '${log.message}/inner'),
              ),
              transformer: (log) =>
                  Log.copy(log, message: '${log.message}/outer'),
            ),
          );

          logger.i('m');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, 'm/outer/inner');
      expect(errors, isEmpty);
    });

    test('flush and close are delegated to the inner publisher', () async {
      final inner = _LifecyclePublisher();
      final publisher = TransformPublisher(inner, transformer: (log) => log);

      await publisher.flush();
      await publisher.close();

      expect(inner.flushCount, 1);
      expect(inner.closeCount, 1);
    });

    test('flush and close complete for a plain inner publisher', () async {
      final publisher = TransformPublisher(
        const CustomLogPublisher<Log>.noOp(),
        transformer: (log) => log,
      );

      await publisher.flush();
      await publisher.close();
    });

    // Regression: M8 (project review 2026-08-16[4]) — close was neither
    // terminal nor idempotent, and what happened after it depended on
    // whether the wrapped publisher happened to implement Closable.
    test('close is terminal regardless of the inner publisher', () async {
      late Log sample;
      Logger('sampler')
        ..level = Levels.all
        ..publisher = CustomLogPublisher<Log>((log) => sample = log)
        ..i('sample');

      final delivered = <Log>[];
      final publisher = TransformPublisher<Log>(
        CustomLogPublisher(delivered.add),
        transformer: (log) => log,
      );

      await publisher.close();

      expect(publisher.isClosed, isTrue);
      expect(() => publisher.publish(sample), throwsPublisherClosed);
      expect(delivered, isEmpty);
    });

    // Regression: M8
    test('close is idempotent and delegates once', () async {
      final inner = _LifecyclePublisher();
      final publisher = TransformPublisher(inner, transformer: (log) => log);

      await publisher.close();
      await publisher.close();

      expect(inner.closeCount, 1);
    });

    // Regression: H3 (project review 2026-08-20[1]) — an inner close() that
    // threw synchronously escaped before _closeFuture was assigned, so
    // isClosed stayed false and logs kept travelling into a publisher the
    // application had already tried to close. MultiPublisher was right all
    // along: it wraps the call in Future.sync.
    test('close stays terminal when the inner close throws synchronously',
        () async {
      late Log sample;
      Logger('sampler')
        ..level = Levels.all
        ..publisher = CustomLogPublisher<Log>((log) => sample = log)
        ..i('sample');

      final inner = _SyncThrowingClosePublisher();
      final publisher = TransformPublisher<Log>(
        inner,
        transformer: (log) => log,
      );

      Object? closeError;
      try {
        await publisher.close();
      } on Object catch (error) {
        closeError = error;
      }

      expect(closeError, isStateError, reason: 'the failure is not swallowed');
      expect(publisher.isClosed, isTrue);
      expect(() => publisher.publish(sample), throwsPublisherClosed);
      expect(inner.published, isEmpty);

      Object? secondError;
      try {
        await publisher.close();
      } on Object catch (error) {
        secondError = error;
      }

      expect(secondError, same(closeError), reason: 'the same future');
      expect(inner.closeCount, 1);
    });

    // Noted while closing H3 (project review 2026-08-20[1]) and fixed with
    // it: flush() had the asymmetry close() had. A wrapped flush() that
    // throws before its first await threw at the caller's call site rather
    // than failing the future it handed back — MultiPublisher, which routes
    // the same call through Future.sync, did not.
    test('a synchronous throw from the inner flush fails the future', () async {
      final publisher = TransformPublisher<Log>(
        _SyncThrowingClosePublisher(),
        transformer: (log) => log,
      );

      Object? atCallSite;
      Future<void>? flushing;
      try {
        flushing = publisher.flush();
      } on Object catch (error) {
        atCallSite = error;
      }

      expect(atCallSite, isNull, reason: 'a future, not a throw');
      await expectLater(flushing, throwsStateError);
    });

    // Regression: L8 (project review 2026-08-17[1]) — every sibling
    // short-circuits flush() after close(); TransformPublisher delegated
    // unconditionally, so with an inner publisher that is Flushable but not
    // Closable it kept poking a publisher it had already disowned.
    test('flush after close does not touch the wrapped publisher', () async {
      final inner = _LifecyclePublisher();
      final publisher = TransformPublisher(inner, transformer: (log) => log);

      await publisher.close();
      await publisher.flush().timeout(const Duration(seconds: 1));

      expect(inner.flushCount, 0);
    });

    // Regression: C1 (project review 2026-08-17[1]) — a withParam adapter did
    // not implement Closable, so the switch on _inner fell through to a no-op
    // and the wrapped shared queue was never drained.
    test('close drains a wrapped withParam adapter', () async {
      final handled = <String?>[];
      final inner = AsyncPublisherWithParam<String, Log>((param, log) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        handled.add(log.message);
      });
      final publisher = TransformPublisher<Log>(
        inner.withParam('p'),
        transformer: (log) => log,
      );
      setUpLogger(publisher);

      logger.i('hello');
      await publisher.close().timeout(const Duration(seconds: 2));

      expect(handled, ['hello']);
      expect(inner.isClosed, isTrue);
    });
  });
}
