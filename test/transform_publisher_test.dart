import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

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
  });
}
