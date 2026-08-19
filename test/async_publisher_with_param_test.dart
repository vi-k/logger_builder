import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/matchers.dart';

void main() {
  group('AsyncPublisherWithParam', () {
    test('routes the bound param with each log through a shared queue',
        () async {
      final handled = <(String, String?)>[];
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) async {
          await Future<void>.delayed(Duration.zero);
          handled.add((param, log.message));
        },
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('common')
        ..[Levels.error].publisher = publisher.withParam('errors');

      log.i('info');
      log.e('oops');
      await publisher.flush();

      expect(handled, [
        ('common', 'info'),
        ('errors', 'oops'),
      ]);
    });

    test('flush on an idle publisher completes', () async {
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) async {},
      );

      await publisher.flush().timeout(const Duration(seconds: 1));
    });

    test('publish after close throws StateError', () async {
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) {},
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      await publisher.close();

      expect(() => log.i('late'), throwsPublisherClosed);
    });

    // Regression: B9
    test('flush after close completes and does not resurrect the publisher',
        () async {
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) {},
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      await publisher.close();
      await publisher.flush().timeout(const Duration(seconds: 1));

      expect(publisher.isClosed, isTrue);
      expect(() => log.i('late'), throwsPublisherClosed);
    });

    // Regression: CR1 (cross-review)
    test('overlapping flush calls both complete and lose no logs', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          handled.add(log.message);
        },
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('one');
      final flush1 = publisher.flush();
      log.i('two');
      final flush2 = publisher.flush();
      log.i('three');
      await flush1.timeout(const Duration(seconds: 2));
      await flush2.timeout(const Duration(seconds: 2));
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(handled, ['one', 'two', 'three']);
    });

    // Regression: B5
    test(
        'onError receives an error thrown by handle '
        'and the pipeline continues', () async {
      final handled = <String?>[];
      final errors = <Object>[];
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) async {
          if (log.message == 'bad') {
            throw StateError('boom');
          }
          handled.add(log.message);
        },
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('p');

      log.i('bad');
      log.i('good');
      await publisher.flush();

      expect(handled, ['good']);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('AsyncFormatterWithParam', () {
    // Regression: B3
    test(
        'with Out = Object? output receives the formatted value, '
        'not a Future', () async {
      final outputs = <Object?>[];
      final publisher = AsyncFormatterWithParam<String, Log, Object?>(
        format: (param, log) async => '$param:${log.message}',
        output: (param, out) => outputs.add(out),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('ctx');

      log.i('msg');
      await publisher.flush();

      expect(outputs, ['ctx:msg']);
    });

    // Regression: H4 (project review 2026-08-16[4]) — the synchronous arm of
    // the format switch was never executed by any test.
    test('a synchronous format still reaches output', () async {
      final outputs = <Object?>[];
      final publisher = AsyncFormatterWithParam<String, Log, String>(
        format: (param, log) => '$param:${log.message}',
        output: (param, out) => outputs.add(out),
      );
      final log = Logger('test')
        ..level = Levels.all
        ..publisher = publisher.withParam('ctx');

      log.i('msg');
      await publisher.flush();

      expect(outputs, ['ctx:msg']);
    });
  });
}
