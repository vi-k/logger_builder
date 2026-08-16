import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

List<(String, String?)> entriesOf(List<(String, Log)> entries) =>
    entries.map((entry) => (entry.$1, entry.$2.message)).toList();

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
      expect(() => log.i('b'), throwsStateError);
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
  });
}
