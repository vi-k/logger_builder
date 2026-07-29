import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

Logger makeLogger(CustomLogPublisher<Log> publisher) => Logger('test')
  ..level = Levels.all
  ..publisher = publisher;

List<String?> messagesOf(List<Log> logs) =>
    logs.map((log) => log.message).toList();

void main() {
  group('AsyncPublisherWithBuffer', () {
    // Regression: B1
    test('flush on an idle publisher completes immediately', () async {
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {});

      await publisher.flush().timeout(const Duration(seconds: 1));
    });

    // Regression: B1
    test('flush after the queue has drained completes', () async {
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {});
      final log = makeLogger(publisher);

      log.i('one');
      await publisher.flush().timeout(const Duration(seconds: 1));
      await publisher.flush().timeout(const Duration(seconds: 1));
    });

    test('collects logs published in the same turn into one batch', () async {
      final batches = <List<String?>>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) async => batches.add(messagesOf(logs)),
      );
      final log = makeLogger(publisher);

      log.d('a');
      log.i('b');
      log.e('c');
      await publisher.flush();

      expect(batches, [
        ['a', 'b', 'c'],
      ]);
    });

    test('sync mode batches and flushes', () async {
      final batches = <List<String?>>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) async => batches.add(messagesOf(logs)),
        sync: true,
      );
      final log = makeLogger(publisher);

      log.i('a');
      log.i('b');
      await publisher.flush();

      expect(batches.expand((batch) => batch), ['a', 'b']);
    });

    test('flush drains logs published after it was called', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        handled.addAll(messagesOf(logs));
      });
      final log = makeLogger(publisher);

      log.i('one');
      final flushFuture = publisher.flush();
      log.i('two');
      await flushFuture;

      expect(handled, ['one', 'two']);
    });

    test('retryBuffer entries are retried at the front of the next batch',
        () async {
      var failFirst = true;
      final gate = Completer<void>();
      final batches = <List<String?>>[];
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {
        if (failFirst) {
          failFirst = false;
          retry.addAll(logs);
          // Hold the first batch open until 'b' is published.
          await gate.future;
          return;
        }
        batches.add(messagesOf(logs));
      });
      final log = makeLogger(publisher);

      log.i('a');
      await Future<void>.delayed(Duration.zero);
      log.i('b');
      gate.complete();
      await publisher.flush().timeout(const Duration(seconds: 1));

      expect(batches, [
        ['a', 'b'],
      ]);
    });

    // Regression: B5
    test(
        'an error thrown by handle reports to onError, keeps the '
        'retryBuffer, and flush completes', () async {
      var first = true;
      final errors = <Object>[];
      final batches = <List<String?>>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) async {
          if (first) {
            first = false;
            retry.addAll(logs);
            throw StateError('boom');
          }
          batches.add(messagesOf(logs));
        },
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = makeLogger(publisher);

      log.i('a');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(errors, [isA<StateError>()]);
      expect(batches, [
        ['a'],
      ]);
    });

    // Regression: CR2 (cross-review)
    test('a throwing onError does not stall the pipeline (sync handle)',
        () async {
      var first = true;
      final batches = <List<String?>>[];
      final zoneErrors = <Object>[];
      late AsyncPublisherWithBuffer<Log> publisher;
      runZonedGuarded(
        () {
          publisher = AsyncPublisherWithBuffer<Log>(
            (logs, retry) {
              if (first) {
                first = false;
                retry.addAll(logs);
                throw StateError('boom');
              }
              batches.add(messagesOf(logs));
            },
            onError: (error, stackTrace) => throw StateError('handler boom'),
          );
          makeLogger(publisher).i('a');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(batches, [
        ['a'],
      ]);
      expect(zoneErrors, [isA<StateError>()]);
    });

    // Regression: CR2 (cross-review)
    test('a throwing onError does not stall the pipeline (async handle)',
        () async {
      var first = true;
      final batches = <List<String?>>[];
      final zoneErrors = <Object>[];
      late AsyncPublisherWithBuffer<Log> publisher;
      runZonedGuarded(
        () {
          publisher = AsyncPublisherWithBuffer<Log>(
            (logs, retry) async {
              if (first) {
                first = false;
                retry.addAll(logs);
                throw StateError('boom');
              }
              batches.add(messagesOf(logs));
            },
            onError: (error, stackTrace) => throw StateError('handler boom'),
          );
          makeLogger(publisher).i('a');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(batches, [
        ['a'],
      ]);
      expect(zoneErrors, [isA<StateError>()]);
    });

    // Regression: CR3 (cross-review)
    test('close processes logs published during an in-flight batch', () async {
      final gate = Completer<void>();
      final batches = <List<String?>>[];
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {
        batches.add(messagesOf(logs));
        if (!gate.isCompleted) {
          await gate.future;
        }
      });
      final log = makeLogger(publisher);

      log.i('one');
      await Future<void>.delayed(Duration.zero);
      log.i('two');
      final closeFuture = publisher.close();
      gate.complete();
      await closeFuture.timeout(const Duration(seconds: 2));

      expect(batches, [
        ['one'],
        ['two'],
      ]);
    });

    // Regression: CR3 (cross-review) — retries after close are dropped
    test('close completes even when the handler keeps retrying', () async {
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) async => retry.addAll(logs),
      );
      final log = makeLogger(publisher);

      log.i('a');
      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: B9
    test('publish after close throws StateError', () async {
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) async => retry.addAll(logs),
      );
      final log = makeLogger(publisher);

      log.i('a');
      await publisher.close();

      expect(publisher.isClosed, isTrue);
      expect(() => log.i('b'), throwsStateError);
    });

    // Regression: B9
    test('flush after close completes immediately', () async {
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {});

      await publisher.close();
      await publisher.flush().timeout(const Duration(seconds: 1));
    });
  });

  group('AsyncFormatterWithBuffer', () {
    test('formats a batch and outputs it', () async {
      final outputs = <String>[];
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) async => messagesOf(logs).join(','),
        output: (out, logs, retry) => outputs.add(out),
      );
      final log = makeLogger(publisher);

      log.i('a');
      log.i('b');
      await publisher.flush();

      expect(outputs, ['a,b']);
    });

    // Regression: B4
    test(
        'remainingLogs reflects retryBuffer additions made during '
        'an async format', () async {
      var first = true;
      final remainings = <List<String?>>[];
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) async {
          await Future<void>.delayed(Duration.zero);
          if (first) {
            first = false;
            retry.add(logs.first);
          }
          return 'batch';
        },
        output: (out, remaining, retry) =>
            remainings.add(messagesOf(remaining)),
      );
      final log = makeLogger(publisher);

      log.i('a');
      log.i('b');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(remainings.first, ['b']);
    });

    // Regression: B3
    test(
        'with Out = Object? output receives the formatted value, '
        'not a Future', () async {
      final outputs = <Object?>[];
      final publisher = AsyncFormatterWithBuffer<Log, Object?>(
        format: (logs, retry) async => messagesOf(logs).join(','),
        output: (out, logs, retry) => outputs.add(out),
      );
      final log = makeLogger(publisher);

      log.i('a');
      await publisher.flush();

      expect(outputs, ['a']);
    });
  });
}
