import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/variable_logger.dart';

void main() {
  group('CustomLevelLogger', () {
    // Regression: B7
    test('an empty name throws ArgumentError', () {
      expect(
        () => LevelLogger(level: Levels.info, name: ''),
        throwsArgumentError,
      );
    });

    test('shortName defaults to the first character of the name', () {
      expect(LevelLogger(level: Levels.info, name: 'info').shortName, 'i');
    });

    // Regression: B7
    test('shortName handles a non-BMP first character', () {
      final levelLogger = LevelLogger(level: Levels.info, name: '🔥fire');

      expect(levelLogger.shortName, '🔥');
    });

    test('an explicit shortName is respected', () {
      final levelLogger =
          LevelLogger(level: Levels.info, name: 'info', shortName: 'INF');

      expect(levelLogger.shortName, 'INF');
    });

    test('setting a publisher on an unattached level logger throws StateError',
        () {
      final levelLogger = LevelLogger(level: Levels.info, name: 'info');

      expect(
        () => levelLogger.publisher = const CustomLogPublisher.noOp(),
        throwsStateError,
      );
    });

    // Regression: M1 (project review 2026-08-16[4]) — Levels.all and
    // Levels.off are thresholds, not levels: a level logger registered at
    // Levels.off stayed enabled with `logger.level = Levels.off`, silently
    // defeating "logging is completely disabled".
    test('a level at or beyond the thresholds throws ArgumentError', () {
      expect(
        () => LevelLogger(level: Levels.off, name: 'nope'),
        throwsArgumentError,
      );
      expect(
        () => LevelLogger(level: Levels.all, name: 'nope'),
        throwsArgumentError,
      );
      expect(
        () => LevelLogger(level: -1, name: 'nope'),
        throwsArgumentError,
      );
      expect(
        () => LevelLogger(level: 5000, name: 'nope'),
        throwsArgumentError,
      );
    });

    // Regression: M2 (project review 2026-08-16[4]) — one level logger
    // registered in two loggers used to hand the first logger's logs to the
    // second one's publisher and transformer, without a word.
    test('registering one level logger in two loggers throws StateError', () {
      final shared = VarLevelLogger(level: Levels.info, name: 'info');

      expect(() => SharedLevelLogger(shared), returnsNormally);
      expect(() => SharedLevelLogger(shared), throwsStateError);
    });
  });

  group('CustomLogger', () {
    test('isLoggable respects the current level', () {
      final log = Logger('test')..level = Levels.warning;

      expect(log.isLoggable(Levels.error), isTrue);
      expect(log.isLoggable(Levels.warning), isTrue);
      expect(log.isLoggable(Levels.info), isFalse);
    });

    test('operator [] throws StateError for an unregistered level', () {
      final log = Logger('test');

      expect(() => log[Levels.finest], throwsStateError);
    });

    test('registering a duplicate level throws StateError', () {
      expect(
        () => VarLogger([Levels.info, Levels.info]),
        throwsStateError,
      );
    });

    // Regression: M20 (project review 2026-08-17[1]) — nothing pinned the
    // documented default. Almost every test assigns `level` first, so the
    // window between registerLevel and that first assignment was untested:
    // making _attach enable every level unconditionally passed the whole
    // suite, and a logger used without touching `level` would have logged
    // everything instead of nothing.
    test('a freshly built logger has every level disabled', () {
      final log = VarLogger([Levels.finest, Levels.info, Levels.severe]);

      expect(log.level, Levels.off);
      for (final level in log.levels) {
        expect(
          log[level].isEnabled,
          isFalse,
          reason: 'level $level must start disabled',
        );
      }
    });

    test('a freshly built logger publishes nothing', () {
      final published = <String?>[];
      final log = VarLogger([Levels.info])
        ..publisher = CustomLogPublisher((log) => published.add(log.message));

      log.logAt(Levels.info)('before any level assignment');

      expect(published, isEmpty);
    });
  });
}
