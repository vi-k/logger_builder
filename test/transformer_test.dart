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
      final child = logger.withAddedName('child');

      child.i('secret');

      expect(published.single.message, '***');
      expect(child.transformerLinked, isTrue);
    });

    test('an assignment on the parent propagates to linked subloggers', () {
      final child = logger.withAddedName('child');
      logger.transformer = (log) => Log.copy(log, message: '***');

      child.i('secret');

      expect(published.single.message, '***');
    });

    test('an assignment on the child detaches it from the parent', () {
      final child = logger.withAddedName('child')
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
      final child = logger.withAddedName('child');
      child.transformer = child.transformer;
      logger.transformer = (log) => Log.copy(log, message: 'parent');

      child.i('secret');

      expect(published.single.message, 'secret');
      expect(child.transformerLinked, isFalse);
    });

    test('relink() re-inherits the parent transformer', () {
      logger.transformer = (log) => Log.copy(log, message: 'parent');
      final child = logger.withAddedName('child')
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

      expect(published, hasLength(1));
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
  });
}
