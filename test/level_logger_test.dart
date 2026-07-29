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
  });
}
