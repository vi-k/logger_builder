import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/matchers.dart';

Logger makeLogger(CustomLogPublisher<Log> publisher) => Logger('test')
  ..level = Levels.all
  ..publisher = publisher;

void main() {
  // Regression: M15 (project review 2026-08-16[4]) — both "sync mode" tests
  // only checked ordering, which is identical in async mode, so hardcoding
  // sync: false in every controller kept the whole suite green.
  group('sync flag', () {
    test('sync: true runs the handler before publish returns', () {
      final handled = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) => handled.add(log.message),
        sync: true,
      );
      makeLogger(publisher).i('a');

      expect(handled, ['a']);
    });

    test('sync: false defers the handler', () {
      final handled = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) => handled.add(log.message),
      );
      makeLogger(publisher).i('a');

      expect(handled, isEmpty);
    });
  });

  group('AsyncPublisher', () {
    test('processes logs sequentially in publish order', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisher<Log>((log) async {
        await Future<void>.delayed(Duration.zero);
        handled.add(log.message);
      });
      final log = makeLogger(publisher);

      log.d('one');
      log.i('two');
      log.e('three');
      await publisher.flush();

      expect(handled, ['one', 'two', 'three']);
    });

    test('sync mode processes logs in publish order', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) => handled.add(log.message),
        sync: true,
      );
      final log = makeLogger(publisher);

      log.i('one');
      log.i('two');
      await publisher.flush();

      expect(handled, ['one', 'two']);
    });

    test('flush on an idle publisher completes', () async {
      final publisher = AsyncPublisher<Log>((log) async {});

      await publisher.flush().timeout(const Duration(seconds: 1));
    });

    test('flush completes only after queued logs are handled', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisher<Log>((log) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        handled.add(log.message);
      });
      final log = makeLogger(publisher);

      log.i('one');
      log.i('two');
      await publisher.flush();

      expect(handled, ['one', 'two']);
    });

    test('publish after close throws StateError', () async {
      final publisher = AsyncPublisher<Log>((log) {});
      final log = makeLogger(publisher);

      await publisher.close();

      expect(() => log.i('late'), throwsPublisherClosed);
    });

    test('close is idempotent', () async {
      final publisher = AsyncPublisher<Log>((log) {});

      await publisher.close();
      await publisher.close();
    });

    // Regression: B9
    test('flush after close completes and does not resurrect the publisher',
        () async {
      final publisher = AsyncPublisher<Log>((log) {});
      final log = makeLogger(publisher);

      await publisher.close();
      await publisher.flush().timeout(const Duration(seconds: 1));

      expect(publisher.isClosed, isTrue);
      expect(() => log.i('late'), throwsPublisherClosed);
    });

    // Regression: B5
    test(
        'onError receives an error thrown by an async handle '
        'and the pipeline continues', () async {
      final handled = <String?>[];
      final errors = <Object>[];
      final publisher = AsyncPublisher<Log>(
        (log) async {
          if (log.message == 'bad') {
            throw StateError('boom');
          }
          handled.add(log.message);
        },
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = makeLogger(publisher);

      log.i('good');
      log.i('bad');
      log.i('after');
      await publisher.flush();

      expect(handled, ['good', 'after']);
      expect(errors, [isA<StateError>()]);
    });

    // Regression: CR1 (cross-review)
    test('overlapping flush calls both complete and lose no logs', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisher<Log>((log) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        handled.add(log.message);
      });
      final log = makeLogger(publisher);

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

    // Regression: CR4 (cross-review 2026-07-29) — awaiting close() from
    // inside handle deadlocks, and that was closed by documenting it rather
    // than by code. This test guards the half that *works*: starting the
    // close from the handler without awaiting it. Anything that ever turns
    // the documented rule into a thrown StateError has to keep this
    // working, because a sink that discovers it is dead and shuts itself
    // down is a real pattern and a legitimate one.
    test('a handler may start a close without awaiting it', () async {
      late AsyncPublisher<Log> publisher;
      final handled = <String?>[];
      var returnedFromHandler = false;
      publisher = AsyncPublisher<Log>((log) async {
        handled.add(log.message);
        unawaited(publisher.close());
        returnedFromHandler = true;
      });
      makeLogger(publisher).i('one');

      await publisher.close().timeout(const Duration(seconds: 2));

      expect(handled, ['one']);
      expect(returnedFromHandler, isTrue);
      expect(publisher.isClosed, isTrue);
    });

    // Regression: L9 (project review 2026-08-20[1]) — the dartdoc promises
    // that a flush during a close hands back *that same* future, and only
    // the observable half of it was ever checked: that the drain is waited
    // out. Removing the early return from flush() left the suite green,
    // because closing the controller drains the queue anyway.
    test('flush during a close hands back that very future', () async {
      final publisher = AsyncPublisher<Log>((log) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      makeLogger(publisher).i('one');
      final closing = publisher.close();

      expect(identical(publisher.flush(), closing), isTrue);
      expect(
        identical(publisher.close(), closing),
        isTrue,
        reason: 'and close',
      );

      await closing.timeout(const Duration(seconds: 2));
    });

    // M8 (project review 2026-08-20[1]) — a flush queued behind another one
    // re-checks for a close that started while it waited, and hands back
    // that close instead of draining a queue the close is already draining.
    //
    // Honest about what this test is: a contract test, not a guard. The
    // finding expected the re-check to be observable, and it is not —
    // removing it leaves this test green, because the second flush then
    // waits on the very controller the close is draining and cannot return
    // any earlier. What the test does catch is the contract itself: a
    // queued flush that ever started answering before the drain finished.
    test('a queued flush waits for a close that started meanwhile', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisher<Log>((log) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        handled.add(log.message);
      });
      final log = makeLogger(publisher);

      log.i('one');
      final first = publisher.flush();
      final second = publisher.flush();
      log.i('two');
      final closing = publisher.close();

      await second.timeout(const Duration(seconds: 2));

      expect(
        handled,
        ['one', 'two'],
        reason: 'the queued flush answers for the close that is draining',
      );

      await Future.wait([first, closing]).timeout(const Duration(seconds: 2));
    });

    // Regression: CR2 (cross-review) — unbuffered variant keeps flowing
    test(
        'a throwing onError is reported to the zone '
        'and the queue continues', () async {
      final handled = <String?>[];
      final zoneErrors = <Object>[];
      late AsyncPublisher<Log> publisher;
      runZonedGuarded(
        () {
          publisher = AsyncPublisher<Log>(
            (log) {
              if (log.message == 'bad') {
                throw StateError('boom');
              }
              handled.add(log.message);
            },
            onError: (error, stackTrace) => throw StateError('handler boom'),
          );
          makeLogger(publisher)
            ..i('bad')
            ..i('good');
        },
        (error, stackTrace) => zoneErrors.add(error),
      );
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(handled, ['good']);
      expect(zoneErrors, isNotEmpty);
    });

    // Regression: B5
    test('onError receives an error thrown by a sync handle', () async {
      final errors = <Object>[];
      final publisher = AsyncPublisher<Log>(
        (log) => throw StateError('boom'),
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = makeLogger(publisher);

      log.i('bad');
      await publisher.flush();

      expect(errors, [isA<StateError>()]);
    });

    // Regression: B5
    test(
        'without onError the error is reported to the current zone '
        'and the pipeline continues', () async {
      final handled = <String?>[];
      final errors = <Object>[];
      late AsyncPublisher<Log> publisher;
      runZonedGuarded(
        () {
          publisher = AsyncPublisher<Log>((log) {
            if (log.message == 'bad') {
              throw StateError('boom');
            }
            handled.add(log.message);
          });
          makeLogger(publisher)
            ..i('bad')
            ..i('good');
        },
        (error, stackTrace) => errors.add(error),
      );
      await publisher.flush();

      expect(handled, ['good']);
      expect(errors, [isA<StateError>()]);
    });
  });

  group('AsyncFormatter', () {
    test('formats and outputs with a concrete Out type', () async {
      final outputs = <String>[];
      final publisher = AsyncFormatter<Log, String>(
        format: (log) async => 'formatted:${log.message}',
        output: outputs.add,
      );
      final log = makeLogger(publisher);

      log.i('msg');
      await publisher.flush();

      expect(outputs, ['formatted:msg']);
    });

    // Regression: B3
    test(
        'with Out = Object? output receives the formatted value, '
        'not a Future', () async {
      final outputs = <Object?>[];
      final publisher = AsyncFormatter<Log, Object?>(
        format: (log) async => 'formatted:${log.message}',
        output: outputs.add,
      );
      final log = makeLogger(publisher);

      log.i('msg');
      await publisher.flush();

      expect(outputs, ['formatted:msg']);
    });

    // Regression: H4 (project review 2026-08-16[4]) — the synchronous arm of
    // the format switch was never executed by any test, so a regression there
    // would have dropped every log without a trace.
    test('a synchronous format still reaches output', () async {
      final outputs = <String>[];
      final publisher = AsyncFormatter<Log, String>(
        format: (log) => 'formatted:${log.message}',
        output: outputs.add,
      );
      final log = makeLogger(publisher);

      log.i('msg');
      await publisher.flush();

      expect(outputs, ['formatted:msg']);
    });
  });

  group('AsyncPublisher zone pinning', () {
    // Regression: coverage audit for the 2026-08-19[2] review — `_listen`
    // wraps the subscription in the construction zone, and its comment says
    // why: `flush` re-subscribes, so subscribing from there would silently
    // move every later zone-reported handler error to whoever happened to
    // flush last. Deleting the wrapper broke no test.
    test('a flush does not move where a handler error is reported', () async {
      final constructionZone = <Object>[];
      final flushZone = <Object>[];
      late final AsyncPublisher<Log> publisher;

      runZonedGuarded(
        () => publisher = AsyncPublisher<Log>((log) {
          throw StateError('handler down');
        }),
        (error, stackTrace) => constructionZone.add(error),
      );

      Future<void>? flushing;
      runZonedGuarded(
        () {
          flushing = publisher.flush();
        },
        (error, stackTrace) => flushZone.add(error),
      );
      await flushing;

      Logger('test')
        ..level = Levels.all
        ..publisher = publisher
        ..i('boom');
      await publisher.close().timeout(const Duration(seconds: 2));

      expect(constructionZone, hasLength(1));
      expect(flushZone, isEmpty, reason: 'the flusher must not inherit it');
    });
  });
}
