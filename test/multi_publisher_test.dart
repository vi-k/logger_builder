import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

final class _RecordingPublisher implements CustomLogPublisher<Log> {
  final received = <String?>[];

  @override
  void publish(Log log) => received.add(log.message);
}

final class _ThrowingPublisher implements CustomLogPublisher<Log> {
  @override
  void publish(Log log) => throw StateError('broken publisher');
}

final class _FlushTrackingPublisher
    implements CustomLogPublisher<Log>, HasFlush {
  bool flushed = false;

  @override
  void publish(Log log) {}

  @override
  Future<void> flush() async {
    flushed = true;
  }
}

final class _ThrowingFlushPublisher
    implements CustomLogPublisher<Log>, HasFlush {
  @override
  void publish(Log log) {}

  @override
  Future<void> flush() => throw StateError('broken flush');
}

void main() {
  group('MultiPublisher', () {
    Logger loggerWith(MultiPublisher<Log> publisher) => Logger('root')
      ..level = Levels.all
      ..publisher = publisher;

    group('publish', () {
      test('continues delivering to remaining publishers when one throws', () {
        final before = _RecordingPublisher();
        final after = _RecordingPublisher();
        final multi =
            MultiPublisher<Log>([before, _ThrowingPublisher(), after]);
        final log = loggerWith(multi);

        runZonedGuarded(() => log.i('hello'), (error, stackTrace) {});

        expect(before.received, ['hello']);
        expect(after.received, ['hello']);
      });

      test('passes the failing publisher and error to onError', () {
        final good = _RecordingPublisher();
        final throwing = _ThrowingPublisher();
        final records = <(CustomLogPublisher<Log>, Object, StackTrace)>[];
        final multi = MultiPublisher<Log>(
          [throwing, good],
          onError: (publisher, error, stackTrace) =>
              records.add((publisher, error, stackTrace)),
        );
        final log = loggerWith(multi);

        expect(() => log.i('hello'), returnsNormally);

        expect(good.received, ['hello']);
        final (publisher, error, _) = records.single;
        expect(publisher, same(throwing));
        expect(error, isA<StateError>());
      });

      test('without onError reports the error to the zone handler', () {
        final good = _RecordingPublisher();
        final multi = MultiPublisher<Log>([_ThrowingPublisher(), good]);
        final log = loggerWith(multi);
        final errors = <Object>[];

        runZonedGuarded(() => log.i('hello'), (error, _) => errors.add(error));

        expect(good.received, ['hello']);
        expect(errors, [isA<StateError>()]);
      });
    });

    group('flush', () {
      test('flushes remaining publishers when one flush throws synchronously',
          () async {
        final tracking = _FlushTrackingPublisher();
        final multi =
            MultiPublisher<Log>([_ThrowingFlushPublisher(), tracking]);

        await expectLater(
          Future.sync(multi.flush),
          throwsA(isA<ParallelWaitError<Object?, Object?>>()),
        );
        expect(tracking.flushed, isTrue);
      });
    });
  });
}
