import 'dart:async';

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

      // A copy with an error but no stackTrace does NOT derive the trace
      // again (not even from error.stackTrace) and does not pick up the
      // original's trace — both are assigned verbatim.
      // ignore: avoid_redundant_argument_values
      final copy = Log.copy(original, error: error, stackTrace: null);

      expect(copy.error, same(error));
      expect(copy.stackTrace, isNull);
    });

    // Regression: coverage audit for the 2026-08-19[2] review — the whole
    // group tests `copy`, and `copy` assigns verbatim by contract. Nothing
    // covered the *main* constructor, so a mutation dropping
    // `?? stackTraceFromError(error)` survived and every log carrying a
    // thrown Error would have lost its trace in silence.
    test('the main constructor derives the trace from a thrown Error', () {
      late final StateError thrown;
      try {
        throw StateError('boom');
        // ignore: avoid_catching_errors
      } on StateError catch (error) {
        thrown = error;
      }
      expect(thrown.stackTrace, isNotNull);

      final log = capture((logger) => logger.e('fail', error: thrown));

      expect(log.stackTrace, same(thrown.stackTrace));
    });

    test('a non-Error carries no derived trace', () {
      final log = capture(
        (logger) => logger.e('fail', error: Exception('plain')),
      );

      expect(log.stackTrace, isNull);
    });

    // Regression: coverage audit — `zone` defaulting to `Zone.current` is
    // sold by its dartdoc as the way a formatter reads zone-locals, and
    // swapping it for `Zone.root` broke nothing.
    test('the main constructor captures the zone of the call', () {
      late final Log log;

      runZoned(
        () => log = capture((logger) => logger.i('hello')),
        zoneValues: {#requestId: 'r-1'},
      );

      expect(log.zone[#requestId], 'r-1');
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
