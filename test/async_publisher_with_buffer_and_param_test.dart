import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/matchers.dart';

List<(String, String?)> entriesOf(List<(String, Log)> entries) =>
    entries.map((entry) => (entry.$1, entry.$2.message)).toList();

/// A log with value equality — legal for a user subclass of [CustomLog], and
/// the case in which a structurally keyed map conflates two distinct logs.
@immutable
final class EqLog extends CustomLog {
  final String message;

  EqLog(super.levelLogger, this.message);

  @override
  bool operator ==(Object other) => other is EqLog && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

void main() {
  group('AsyncPublisherWithBufferAndParam', () {
    // Regression: B1
    test('flush on an idle publisher completes immediately', () async {
      final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
        (entries, retry) async {},
      );

      await publisher.flush().timeout(const Duration(seconds: 1));
    });

    test('collects parameterized logs into one batch', () async {
      final batches = <List<(String, String?)>>[];
      final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
        (entries, retry) async => batches.add(entriesOf(entries)),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('common')
        ..[Levels.error].publisher = publisher.withParam('errors');

      log.i('info');
      log.e('oops');
      await publisher.flush().timeout(const Duration(seconds: 1));

      expect(batches, [
        [('common', 'info'), ('errors', 'oops')],
      ]);
    });

    // Regression: B5
    test(
        'an error thrown by handle reports to onError, keeps the '
        'retryBuffer, and flush completes', () async {
      var first = true;
      final errors = <Object>[];
      final batches = <List<(String, String?)>>[];
      final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
        (entries, retry) async {
          if (first) {
            first = false;
            retry.addAll(entries);
            throw StateError('boom');
          }
          batches.add(entriesOf(entries));
        },
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('a');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(errors, [isA<StateError>()]);
      expect(batches, [
        [('p', 'a')],
      ]);
    });

    // Regression: B9
    test('publish after close throws StateError', () async {
      final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
        (entries, retry) async => retry.addAll(entries),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('a');
      await publisher.close();

      expect(publisher.isClosed, isTrue);
      expect(() => log.i('b'), throwsPublisherClosed);
    });
  });

  group('AsyncFormatterWithBufferAndParam', () {
    // Regression: B4
    test(
        'remainingLogs reflects retryBuffer additions made during '
        'an async format', () async {
      var first = true;
      final remainings = <List<(String, String?)>>[];
      final publisher = AsyncFormatterWithBufferAndParam<String, Log, String>(
        format: (entries, retry) async {
          await Future<void>.delayed(Duration.zero);
          if (first) {
            first = false;
            retry.add(entries.first);
          }
          return 'batch';
        },
        output: (out, remaining, retry) => remainings.add(entriesOf(remaining)),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('a');
      log.i('b');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(remainings.first, [('p', 'b')]);
    });

    // Regression: B3
    test(
        'with Out = Object? output receives the formatted value, '
        'not a Future', () async {
      final outputs = <Object?>[];
      final publisher = AsyncFormatterWithBufferAndParam<String, Log, Object?>(
        format: (entries, retry) async =>
            entries.map((entry) => entry.$2.message).join(','),
        output: (out, entries, retry) => outputs.add(out),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('a');
      await publisher.flush().timeout(const Duration(seconds: 1));

      expect(outputs, ['a']);
    });

    // Regression: H4 (project review 2026-08-16[4]) — the synchronous arm of
    // the format switch was never executed by any test.
    test('a synchronous format still reaches output', () async {
      final outputs = <Object?>[];
      final publisher = AsyncFormatterWithBufferAndParam<String, Log, String>(
        format: (entries, retry) =>
            entries.map((entry) => entry.$2.message).join(','),
        output: (out, entries, retry) => outputs.add(out),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('a');
      log.i('b');
      await publisher.flush().timeout(const Duration(seconds: 1));

      expect(outputs, ['a,b']);
    });

    // Regression: H3 (project review 2026-08-16[4]) — a throwing format used
    // to drop the whole batch, with no point at which the caller could hand
    // it back.
    test('a throwing format retries the whole batch', () async {
      final outputs = <Object?>[];
      final errors = <Object>[];
      var first = true;
      final publisher = AsyncFormatterWithBufferAndParam<String, Log, String>(
        format: (entries, retry) {
          if (first) {
            first = false;
            throw StateError('format boom');
          }

          return entries.map((entry) => entry.$2.message).join(',');
        },
        output: (out, entries, retry) => outputs.add(out),
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('a');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(errors.single, isStateError);
      expect(outputs, ['a']);
    });

    // Regression: H1 (project review 2026-08-17[1]) — the counted map compared
    // records structurally, so a Log with value equality made two distinct
    // logs interchangeable: the entry handed back to the retry buffer went to
    // output *and* back into the queue, while the other one silently vanished.
    test('retrying one of two equal but distinct logs keeps both', () async {
      final levelLogger = Logger('test')[Levels.info];
      final a = EqLog(levelLogger, 'dup');
      final b = EqLog(levelLogger, 'dup');
      expect(a == b, isTrue, reason: 'the fixture must have value equality');
      expect(identical(a, b), isFalse);

      final delivered = <EqLog>[];
      var first = true;
      final publisher = AsyncFormatterWithBufferAndParam<String, EqLog, String>(
        format: (entries, retry) {
          if (first) {
            first = false;
            retry.add(entries[1]);
          }

          return 'batch';
        },
        output: (out, entries, retry) =>
            delivered.addAll(entries.map((entry) => entry.$2)),
      );
      publisher.withParam('p')
        ..publish(a)
        ..publish(b);
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(
        delivered.map((log) => identical(log, a) ? 'a' : 'b').toList(),
        ['a', 'b'],
        reason: 'each distinct log must reach output exactly once',
      );
    });

    // Regression: coverage audit for the 2026-08-19[2] review — the three
    // lifecycle parameters of this class were plumbed into the pipeline and
    // nothing checked that they arrived. Mutations that quietly dropped
    // `onDropped:` and `retryDelay:` from the constructor call both
    // survived, while the same mutation for `onError:` was caught. One test
    // for all three: the budget bounds the attempts, the backoff spaces
    // them out, and what is left over reaches `onDropped`.
    test('maxRetries, retryDelay and onDropped all reach the pipeline',
        () async {
      final stamps = <int>[];
      final dropped = <(String, String?)>[];
      final elapsed = Stopwatch()..start();
      final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
        (entries, retryBuffer) {
          stamps.add(elapsed.elapsedMilliseconds);
          retryBuffer.addAll(entries);
        },
        maxRetries: 2,
        retryDelay: const Duration(milliseconds: 20),
        onDropped: (entries) => dropped.addAll(entriesOf(entries)),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('ctx');

      log.i('undeliverable');
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(stamps, hasLength(3), reason: 'the first attempt plus two');
      expect(dropped, [('ctx', 'undeliverable')]);
      // Stamped inside the handler, not after the wait: 20 ms then 40 ms
      // puts the last attempt past 50, while a dropped `retryDelay` would
      // put all three inside the first millisecond.
      expect(stamps.last, greaterThan(50));

      await publisher.close().timeout(const Duration(seconds: 2));
    });
  });
}
