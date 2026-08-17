import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

void main() {
  group('CustomLogger.transformer', () {
    late List<Log> published;
    late Logger logger;

    setUp(() {
      published = <Log>[];
      logger = Logger('app')
        ..level = Levels.all
        ..publisher = CustomLogPublisher(published.add);
    });

    test('is applied before the publisher', () {
      logger
        ..transformer = ((log) => Log.copy(log, message: '***'))
        ..i('secret');

      expect(published.single.message, '***');
    });

    test('null transformer (default) publishes the log as is', () {
      logger.i('hello');

      expect(published.single.message, 'hello');
    });

    test('null from transformer drops the log', () {
      logger
        ..transformer = ((log) => null)
        ..i('secret');

      expect(published, isEmpty);
    });

    test('throwing transformer drops the log and reports to the zone', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) => throw StateError('bad transformer'))
            ..i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published, isEmpty);
      expect(errors.single, isA<StateError>());
    });

    test('a sublogger created after the assignment inherits it', () {
      logger.transformer = (log) => Log.copy(log, message: '***');
      final child = logger.child('child');

      child.i('secret');

      expect(published.single.message, '***');
      expect(child.transformerLinked, isTrue);
    });

    test('an assignment on the parent propagates to linked subloggers', () {
      final child = logger.child('child');
      logger.transformer = (log) => Log.copy(log, message: '***');

      child.i('secret');

      expect(published.single.message, '***');
    });

    test('an assignment on the child detaches it from the parent', () {
      final child = logger.child('child')
        ..transformer = ((log) => Log.copy(log, message: 'child'));
      logger.transformer = (log) => Log.copy(log, message: 'parent');

      child.i('secret');
      logger.i('secret');

      expect(published, hasLength(2));
      expect(published[0].message, 'child');
      expect(published[1].message, 'parent');
      expect(child.transformerLinked, isFalse);
    });

    test('self-assignment unlinks without changing the value', () {
      final child = logger.child('child');
      child.transformer = child.transformer;
      logger.transformer = (log) => Log.copy(log, message: 'parent');

      child.i('secret');

      expect(published.single.message, 'secret');
      expect(child.transformerLinked, isFalse);
    });

    test('relink() re-inherits the parent transformer', () {
      logger.transformer = (log) => Log.copy(log, message: 'parent');
      final child = logger.child('child')
        ..transformer = ((log) => Log.copy(log, message: 'child'))
        ..relink()
        ..i('secret');

      expect(published.single.message, 'parent');
      expect(child.transformerLinked, isTrue);
    });

    test('works together with a per-level publisher', () {
      final errorsOnly = <Log>[];
      logger
        ..transformer = ((log) => Log.copy(log, message: '***'))
        ..[Levels.error].publisher = CustomLogPublisher(errorsOnly.add)
        ..i('secret')
        ..e('secret');

      expect(published.single.message, '***');
      expect(errorsOnly.single.message, '***');
    });
  });

  group('CustomLogger.transformer reentrancy', () {
    late List<Log> published;
    late Logger logger;

    setUp(() {
      published = <Log>[];
      logger = Logger('app')
        ..level = Levels.all
        ..publisher = CustomLogPublisher(published.add);
    });

    test('logging through the same logger drops the nested log', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) {
              logger.i('from inside the transformer');

              return Log.copy(log, message: '***');
            })
            ..i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, '***');
      expect(errors.single, isA<StateError>());
    });

    test('a nested call on another level of the same logger is caught', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) {
              logger.d('from inside the transformer');

              return log;
            })
            ..i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      // The outer log is the one that must survive: a guard firing inside
      // out — dropping the outer log and publishing the nested one — would
      // be the worst possible outcome for a masking transformer, and
      // hasLength(1) alone cannot tell the two apart.
      expect(published.single.message, 'secret');
      expect(errors.single, isA<StateError>());
    });

    test('the logger keeps working after a reentrant call', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) {
              if (log.message == 'first') {
                logger.i('from inside the transformer');
              }

              return Log.copy(log, message: '${log.message}!');
            })
            ..i('first')
            ..i('second');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.map((log) => log.message), ['first!', 'second!']);
      expect(errors.single, isA<StateError>());
    });

    test('logging into an unrelated logger is allowed', () {
      final audited = <Log>[];
      final auditLogger = Logger('audit')
        ..level = Levels.all
        ..publisher = CustomLogPublisher(audited.add)
        ..transformer =
            ((log) => Log.copy(log, message: 'audit/${log.message}'));

      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) {
              auditLogger.i('masked');

              return Log.copy(log, message: '***');
            })
            ..i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, '***');
      expect(audited.single.message, 'audit/masked');
      expect(errors, isEmpty);
    });

    test('a cycle between two loggers is caught on the way back', () {
      final other = <Log>[];
      final otherLogger = Logger('other')
        ..level = Levels.all
        ..publisher = CustomLogPublisher(other.add);

      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger.transformer = (log) {
            otherLogger.i('to the other logger');

            return Log.copy(log, message: '***');
          };
          otherLogger.transformer = (log) {
            logger.i('back to the first logger');

            return Log.copy(log, message: 'other');
          };
          logger.i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, '***');
      expect(other.single.message, 'other');
      expect(errors.single, isA<StateError>());
    });

    test('a throwing transformer still releases the guard', () {
      final errors = <Object>[];
      var fail = true;
      runZonedGuarded(
        () {
          logger.transformer = (log) {
            if (fail) {
              throw StateError('bad transformer');
            }

            return Log.copy(log, message: '***');
          };
          logger.i('dropped');
          fail = false;
          logger.i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, '***');
      expect(errors.single, isA<StateError>());
    });

    test('composes with a TransformPublisher without tripping the guard', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger
            ..publisher = TransformPublisher<Log>(
              CustomLogPublisher(published.add),
              transformer: (log) =>
                  Log.copy(log, message: '${log.message}/pub'),
            )
            ..transformer =
                ((log) => Log.copy(log, message: '${log.message}/log'))
            ..i('m');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, 'm/log/pub');
      expect(errors, isEmpty);
    });

    // Regression: M7 (project review 2026-08-16[4]) — a publisher logging
    // into its own logger recursed about 2570 frames into a
    // StackOverflowError, running the transformer once per frame.
    test('a publisher logging into its own logger drops the nested log', () {
      final errors = <Object>[];
      var publishes = 0;
      runZonedGuarded(
        () {
          logger
            ..publisher = CustomLogPublisher<Log>((log) {
              publishes++;
              published.add(log);
              logger.i('from inside the publisher');
            })
            ..i('outer');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(publishes, 1);
      expect(published.single.message, 'outer');
      expect(errors.single, isA<StateError>());
    });

    // Regression: M7 — the same cycle with a transformer installed used to
    // run the transformer once per frame all the way down.
    test('the publisher guard also holds with a transformer installed', () {
      final errors = <Object>[];
      var transformerRuns = 0;
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) {
              transformerRuns++;

              return log;
            })
            ..publisher = CustomLogPublisher<Log>((log) {
              published.add(log);
              logger.i('from inside the publisher');
            })
            ..i('outer');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(transformerRuns, 2, reason: 'outer log plus the nested attempt');
      expect(published.single.message, 'outer');
      expect(errors.single, isA<StateError>());
    });

    // Regression: M5 (project review 2026-08-16[4]) — documents a real limit
    // of the guard rather than a fix: a sublogger is a separate logger with
    // its own flag, so a transformer logging through a linked sublogger is
    // not reentrancy and the nested log IS published.
    test('logging through a linked sublogger is not treated as reentrant', () {
      final errors = <Object>[];
      final child = logger.child('child');
      var transformerRuns = 0;
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) {
              transformerRuns++;
              if (transformerRuns == 1) {
                child.i('via child');
              }

              return log;
            })
            ..i('outer');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(
        published.map((log) => log.message),
        ['via child', 'outer'],
        reason: 'the nested log goes through and is published first',
      );
      expect(errors, isEmpty);
    });

    // Regression: M3 (project review 2026-08-17[1]) — the publisher guard was
    // one flag on the whole logger, so it also rejected a provably
    // terminating pattern: an error publisher noting what it did at info
    // level, through a publisher that logs nothing. The nested log was
    // dropped and a StateError reported.
    test('a publisher logging at another level of the same logger is allowed',
        () {
      final errors = <Object>[];
      final notes = <String?>[];
      runZonedGuarded(
        () {
          logger[Levels.info].publisher =
              CustomLogPublisher<Log>((log) => notes.add(log.message));
          logger[Levels.severe].publisher = CustomLogPublisher<Log>((log) {
            published.add(log);
            logger.i('rotated');
          });
          logger.e('disk full');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published.single.message, 'disk full');
      expect(notes, ['rotated'], reason: 'the nested log must go through');
      expect(errors, isEmpty);
    });

    test('a cycle across two levels of one logger is still caught', () {
      final errors = <Object>[];
      var severePublishes = 0;
      runZonedGuarded(
        () {
          logger[Levels.info].publisher =
              CustomLogPublisher<Log>((log) => logger.e('back to severe'));
          logger[Levels.severe].publisher = CustomLogPublisher<Log>((log) {
            severePublishes++;
            logger.i('to info');
          });
          logger.e('start');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(severePublishes, 1, reason: 'the cycle must not run twice');
      expect(errors.single, isA<StateError>());
    });
  });

  group('CustomLogger.onError', () {
    late List<Log> published;
    late Logger logger;

    setUp(() {
      published = <Log>[];
      logger = Logger('app')
        ..level = Levels.all
        ..publisher = CustomLogPublisher(published.add);
    });

    // Regression: H2 (project review 2026-08-17[1]) — a throwing transformer
    // went to Zone.handleUncaughtError with no way to opt out, and in a plain
    // Dart program that terminates the isolate: a bug in masking code took
    // the process down.
    test('receives a throwing transformer instead of the zone', () {
      final handled = <Object>[];
      final zoneErrors = <Object>[];
      void collect(Object error, StackTrace stackTrace) => handled.add(error);

      runZonedGuarded(
        () {
          logger
            ..onError = collect
            ..transformer = ((log) => throw StateError('masking bug'))
            ..i('secret');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(handled.single, isA<StateError>());
      expect(zoneErrors, isEmpty, reason: 'the zone must not see it');
      expect(published, isEmpty, reason: 'fail-closed still holds');
    });

    test('receives a guard violation instead of the zone', () {
      final handled = <Object>[];
      final zoneErrors = <Object>[];
      void collect(Object error, StackTrace stackTrace) => handled.add(error);

      runZonedGuarded(
        () {
          logger
            ..onError = collect
            ..transformer = ((log) {
              logger.i('from inside the transformer');

              return log;
            })
            ..i('secret');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(handled.single, isA<StateError>());
      expect(zoneErrors, isEmpty);
    });

    // Regression: M1 (project review 2026-08-17[1]) — a throwing publisher
    // surfaced at the `log.i(...)` call site, so a logging call could take
    // down the business logic that made it.
    test('keeps a throwing publisher from reaching the call site', () {
      final handled = <Object>[];
      void collect(Object error, StackTrace stackTrace) => handled.add(error);

      logger
        ..onError = collect
        ..publisher = CustomLogPublisher<Log>((log) {
          throw StateError('sink down');
        });

      expect(() => logger.i('hello'), returnsNormally);
      expect(handled.single, isA<StateError>());
    });

    test('without a handler a throwing publisher still reaches the call site',
        () {
      logger.publisher = CustomLogPublisher<Log>((log) {
        throw StateError('sink down');
      });

      expect(() => logger.i('hello'), throwsStateError);
    });

    test('the logger keeps working after a handled publisher failure', () {
      final handled = <Object>[];
      var fail = true;
      void collect(Object error, StackTrace stackTrace) => handled.add(error);

      logger
        ..onError = collect
        ..publisher = CustomLogPublisher<Log>((log) {
          if (fail) {
            throw StateError('sink down');
          }
          published.add(log);
        });

      logger.i('dropped');
      fail = false;
      logger.i('delivered');

      expect(handled, hasLength(1));
      expect(published.single.message, 'delivered');
    });

    test('a throwing handler goes to the zone and does not wedge logging', () {
      final zoneErrors = <Object>[];
      void boom(Object error, StackTrace stackTrace) =>
          throw StateError('handler boom');

      runZonedGuarded(
        () {
          logger
            ..onError = boom
            ..transformer = ((log) => throw StateError('masking bug'))
            ..i('secret')
            ..transformer = null
            ..i('after');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );

      expect(zoneErrors.single, isA<StateError>());
      expect(published.single.message, 'after');
    });

    test('a sublogger inherits the handler through the parent chain', () {
      final handled = <Object>[];
      void collect(Object error, StackTrace stackTrace) => handled.add(error);

      logger.onError = collect;
      final child = logger.child('child');
      final grandchild = child.child('grandchild');

      expect(child.onError, isNotNull);
      expect(grandchild.onError, isNotNull);

      grandchild
        ..transformer = ((log) => throw StateError('masking bug'))
        ..i('secret');

      expect(handled.single, isA<StateError>());
    });

    test('a sublogger handler overrides the inherited one', () {
      final parentHandled = <Object>[];
      final childHandled = <Object>[];
      void collectParent(Object error, StackTrace stackTrace) =>
          parentHandled.add(error);
      void collectChild(Object error, StackTrace stackTrace) =>
          childHandled.add(error);

      logger.onError = collectParent;
      final child = logger.child('child')
        ..onError = collectChild
        ..transformer = ((log) => throw StateError('masking bug'));

      child.i('secret');

      expect(childHandled, hasLength(1));
      expect(parentHandled, isEmpty);
    });

    test('assigning null restores the inherited handler', () {
      final handled = <Object>[];
      void collect(Object error, StackTrace stackTrace) => handled.add(error);
      void other(Object error, StackTrace stackTrace) {}

      logger.onError = collect;
      final child = logger.child('child')
        ..onError = other
        ..onError = null;

      expect(child.onError, isNotNull, reason: 'the parent handler is back');
    });
  });
}
