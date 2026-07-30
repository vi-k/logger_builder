import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

void main() {
  group('CustomLog.copy', () {
    Log capture(void Function(Logger logger) emit) {
      final logs = <Log>[];
      final logger = Logger('test')
        ..level = Levels.all
        ..publisher = CustomLogPublisher(logs.add);
      emit(logger);

      return logs.single;
    }

    test('preserves level fields, zone and timestamp', () {
      final original = capture((logger) => logger.i('hello'));
      final copy = Log.copy(original, message: 'masked');

      expect(copy.level, original.level);
      expect(copy.levelName, original.levelName);
      expect(copy.shortLevelName, original.shortLevelName);
      expect(copy.zone, same(original.zone));
      expect(copy.timestamp, original.timestamp);
      expect(copy.path, original.path);
      expect(copy.message, 'masked');
    });

    test('keeps the original message when not overridden', () {
      final original = capture((logger) => logger.i('hello'));
      final copy = Log.copy(original);

      expect(copy.message, 'hello');
    });

    test('assigns error and stackTrace verbatim', () {
      late final Error error;
      try {
        throw StateError('boom');
        // ignore: avoid_catching_errors
      } on StateError catch (e) {
        error = e;
      }
      expect(error.stackTrace, isNotNull);

      final original = capture(
        (logger) => logger.e(
          'fail',
          error: error,
          stackTrace: StackTrace.current,
        ),
      );
      expect(original.stackTrace, isNotNull);

      // Копия с error, но без stackTrace НЕ выводит трейс заново (даже
      // из error.stackTrace) и не подхватывает трейс оригинала —
      // значения присваиваются дословно.
      // ignore: avoid_redundant_argument_values
      final copy = Log.copy(original, error: error, stackTrace: null);

      expect(copy.error, same(error));
      expect(copy.stackTrace, isNull);
    });

    test('drops error when copied without one', () {
      final original =
          capture((logger) => logger.e('fail', error: StateError('boom')));
      final copy = Log.copy(original);

      expect(copy.error, isNull);
      expect(copy.stackTrace, isNull);
    });
  });
}
