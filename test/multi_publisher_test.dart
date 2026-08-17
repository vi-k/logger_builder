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
    implements CustomLogPublisher<Log>, Flushable {
  bool flushed = false;

  @override
  void publish(Log log) {}

  @override
  Future<void> flush() async {
    flushed = true;
  }
}

final class _ThrowingFlushPublisher
    implements CustomLogPublisher<Log>, Flushable {
  @override
  void publish(Log log) {}

  @override
  Future<void> flush() => throw StateError('broken flush');
}

final class _ClosableTrackingPublisher
    implements CustomLogPublisher<Log>, Flushable, Closable {
  bool flushed = false;
  bool closed = false;

  @override
  void publish(Log log) {}

  @override
  Future<void> flush() async {
    flushed = true;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _ThrowingClosePublisher
    implements CustomLogPublisher<Log>, Closable {
  @override
  void publish(Log log) {}

  @override
  Future<void> close() => throw StateError('broken close');
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

      // Regression: CR5 (cross-review 0.4.0)
      test(
          'a throwing onError does not interrupt delivery '
          'or escape to the call site', () {
        final good = _RecordingPublisher();
        final zoneErrors = <Object>[];
        runZonedGuarded(
          () {
            final multi = MultiPublisher<Log>(
              [_ThrowingPublisher(), good],
              onError: (publisher, error, stackTrace) =>
                  throw StateError('handler boom'),
            );
            final log = loggerWith(multi);

            expect(() => log.i('hello'), returnsNormally);
          },
          (error, stackTrace) => zoneErrors.add(error),
        );

        expect(good.received, ['hello']);
        expect(zoneErrors, [isA<StateError>()]);
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

      // Regression: B8 (0.4.0)
      test('with onError flush completes and routes the failing publisher',
          () async {
        final tracking = _FlushTrackingPublisher();
        final throwing = _ThrowingFlushPublisher();
        final records = <(CustomLogPublisher<Log>, Object)>[];
        final multi = MultiPublisher<Log>(
          [throwing, tracking],
          onError: (publisher, error, stackTrace) =>
              records.add((publisher, error)),
        );

        await multi.flush().timeout(const Duration(seconds: 1));

        expect(tracking.flushed, isTrue);
        final (publisher, error) = records.single;
        expect(publisher, same(throwing));
        expect(error, isA<StateError>());
      });
    });

    // Regression: CR7 (cross-review 0.4.0)
    test(
        'a throwing onError does not fail flush; the secondary error '
        'goes to the zone', () async {
      final tracking = _FlushTrackingPublisher();
      final zoneErrors = <Object>[];
      late Future<void> flushFuture;
      runZonedGuarded(
        () {
          final multi = MultiPublisher<Log>(
            [_ThrowingFlushPublisher(), tracking],
            onError: (publisher, error, stackTrace) =>
                throw StateError('handler boom'),
          );
          flushFuture = multi.flush();
        },
        (error, stackTrace) => zoneErrors.add(error),
      );
      await flushFuture.timeout(const Duration(seconds: 1));

      expect(tracking.flushed, isTrue);
      expect(zoneErrors, [isA<StateError>()]);
    });

    // Regression: CR6 (cross-review 0.4.0)
    group('closed state', () {
      test('publish after close throws StateError', () async {
        final plain = _RecordingPublisher();
        final multi = MultiPublisher<Log>([plain]);
        final log = loggerWith(multi);

        await multi.close();

        expect(multi.isClosed, isTrue);
        expect(() => log.i('late'), throwsStateError);
        expect(plain.received, isEmpty);
      });

      test('close is idempotent and flush after close completes', () async {
        final closable = _ClosableTrackingPublisher();
        final multi = MultiPublisher<Log>([closable]);

        await multi.close();
        await multi.close();
        await multi.flush().timeout(const Duration(seconds: 1));

        expect(closable.closed, isTrue);
      });
    });

    // Regression: D3 (0.4.0)
    group('close', () {
      test('closes every closable publisher', () async {
        final closable = _ClosableTrackingPublisher();
        final plain = _RecordingPublisher();
        final multi = MultiPublisher<Log>([closable, plain]);

        await multi.close().timeout(const Duration(seconds: 1));

        expect(closable.closed, isTrue);
      });

      test('routes close errors to onError', () async {
        final throwing = _ThrowingClosePublisher();
        final closable = _ClosableTrackingPublisher();
        final records = <CustomLogPublisher<Log>>[];
        final multi = MultiPublisher<Log>(
          [throwing, closable],
          onError: (publisher, error, stackTrace) => records.add(publisher),
        );

        await multi.close().timeout(const Duration(seconds: 1));

        expect(closable.closed, isTrue);
        expect(records, [same(throwing)]);
      });
    });

    // Regression: D5 (0.4.0)
    test('the publisher list is copied at construction', () {
      final first = _RecordingPublisher();
      final list = <CustomLogPublisher<Log>>[first];
      final multi = MultiPublisher<Log>(list);
      final log = loggerWith(multi);
      final late = _RecordingPublisher();
      list.add(late);

      log.i('hello');

      expect(first.received, ['hello']);
      expect(late.received, isEmpty);
    });

    // Regression: D3 (0.4.0)
    test('is Flushable and Closable', () {
      final multi = MultiPublisher<Log>([]);

      expect(multi, isA<Flushable>());
      expect(multi, isA<Closable>());
    });

    // Regression: C1 (project review 2026-08-17[1]) — a withParam adapter
    // implemented neither interface, so _waitAll's type test skipped it:
    // flush and close reported success while the whole shared queue was lost.
    group('withParam adapters inside a MultiPublisher', () {
      test('flush drains the shared queue', () async {
        final handled = <String?>[];
        final inner = AsyncPublisherWithParam<String, Log>((param, log) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          handled.add(log.message);
        });
        final multi = MultiPublisher<Log>([inner.withParam('p')]);
        final log = loggerWith(multi);

        log.i('hello');
        await multi.flush().timeout(const Duration(seconds: 2));

        expect(handled, ['hello']);
        await inner.close();
      });

      test('close drains the shared queue and closes it', () async {
        final handled = <String?>[];
        final inner = AsyncPublisherWithParam<String, Log>((param, log) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          handled.add(log.message);
        });
        final multi = MultiPublisher<Log>([inner.withParam('p')]);
        final log = loggerWith(multi);

        log.i('hello');
        await multi.close().timeout(const Duration(seconds: 2));

        expect(handled, ['hello']);
        expect(inner.isClosed, isTrue);
      });

      test('the buffered variant is drained too', () async {
        final handled = <String?>[];
        final inner = AsyncPublisherWithBufferAndParam<String, Log>(
          (entries, retry) async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            handled.addAll(entries.map((entry) => entry.$2.message));
          },
        );
        final multi = MultiPublisher<Log>([inner.withParam('p')]);
        final log = loggerWith(multi);

        log.i('hello');
        await multi.close().timeout(const Duration(seconds: 2));

        expect(handled, ['hello']);
        expect(inner.isClosed, isTrue);
      });

      test('several adapters over one queue close it once', () async {
        final inner =
            AsyncPublisherWithParam<String, Log>((param, log) async {});
        final multi = MultiPublisher<Log>([
          inner.withParam('a'),
          inner.withParam('b'),
        ]);

        await multi.close().timeout(const Duration(seconds: 2));

        expect(inner.isClosed, isTrue);
      });
    });
  });
}
