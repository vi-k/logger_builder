import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/matchers.dart';
import 'utils/wait.dart';

Logger makeLogger(CustomLogPublisher<Log> publisher) => Logger('test')
  ..level = Levels.all
  ..publisher = publisher;

/// A log with value equality — legal for a user subclass of [CustomLog], and
/// the case that tells an identity-keyed map from a structurally keyed one.
@immutable
final class EqLog extends CustomLog {
  final String message;

  EqLog(super.levelLogger, this.message);

  @override
  bool operator ==(Object other) => other is EqLog && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

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

    // Regression: C1 (project review 2026-08-16[4]) — a handler that keeps
    // handing the batch back used to re-tick through the microtask queue,
    // which never yields: timers, I/O and close() itself were starved.
    //
    // Regression: M7 (project review 2026-08-20[1]) — this guard was
    // disarmed by a feature that arrived after it. With the default
    // maxRetries of 100 the microtask loop ends by itself after a hundred
    // attempts, the delay below then completes, and the test passed with
    // the defect restored. Two things fix that. The budget is raised out of
    // the way so the loop cannot end on its own, and the number of attempts
    // is what is asserted: spaced by a timer they are counted in single
    // digits, while a microtask loop spends the whole budget inside one
    // turn of the event loop. The count also keeps the failure loud — a
    // starved isolate cannot fail a test, it can only hang it, and a hung
    // `dart test` prints nothing at all.
    test('a permanently retrying handler does not starve the event loop',
        () async {
      var attempts = 0;
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) {
          attempts++;
          retry.addAll(logs);
        },
        retryDelay: const Duration(milliseconds: 1),
        maxRetries: 100000,
        onDropped: (logs) {},
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      // A timer at all is the assertion: while the retries were a microtask
      // loop, this delay never completed and the test hung instead.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(attempts, greaterThan(1), reason: 'the batch should be retried');
      expect(
        attempts,
        lessThan(200),
        reason: 'retries go through the event loop, not the microtask queue',
      );

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: C1 — close() used to be reachable only when called
    // synchronously, before the first batch ever ran.
    test('close from a later turn stops a permanently retrying handler',
        () async {
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) => retry.addAll(logs),
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await publisher.close().timeout(const Duration(seconds: 2));

      expect(publisher.isClosed, isTrue);
    });

    // Regression: C1
    test('retryDelay spaces out the attempts', () async {
      var attempts = 0;
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) {
          attempts++;
          retry.addAll(logs);
        },
        retryDelay: const Duration(milliseconds: 10),
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(attempts, greaterThan(0));
      expect(
        attempts,
        lessThan(50),
        reason: 'retryDelay should keep the queue from spinning',
      );

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: C1 (project review 2026-08-19[2]) — a batch handed back
    // was retried for ever. With the default `retryDelay` of zero that was
    // 242 820 handler calls and as many `onError` calls in half a second,
    // from one log whose formatting was deterministically broken. The log
    // was never delivered and never dropped either.
    test('a batch that never succeeds is dropped once the budget is spent',
        () async {
      var attempts = 0;
      final dropped = <String?>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) {
          attempts++;
          retry.addAll(logs);
        },
        maxRetries: 3,
        onDropped: (logs) => dropped.addAll(messagesOf(logs)),
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      await pumpUntil(() => dropped.isNotEmpty);

      expect(attempts, 4, reason: 'the first attempt plus three retries');
      expect(dropped, ['undeliverable']);

      // And it really stops: nothing keeps ticking afterwards.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(attempts, 4);

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: C1 (project review 2026-08-19[2]) — `_drain` waits for an
    // empty queue, and a permanent retry never emptied it, so the documented
    // `await flush(); await close();` shutdown hung on the first line
    // exactly when the logs mattered most.
    test('flush completes once the retry budget is spent', () async {
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) => retry.addAll(logs),
        maxRetries: 2,
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      await publisher.flush().timeout(const Duration(seconds: 2));

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: C1 (project review 2026-08-19[2]) — the budget counts a
    // run of failures, not the lifetime of the publisher: a sink that comes
    // back must get the full allowance again. Note the shape — the first
    // batch must *recover*, not be dropped, or the reset on the drop path
    // hides a missing reset on the success path.
    test('the retry budget resets after a batch that succeeds', () async {
      var failuresLeft = 2;
      var attempts = 0;
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) {
          attempts++;
          if (failuresLeft > 0) {
            failuresLeft--;
            retry.addAll(logs);
          } else {
            handled.addAll(messagesOf(logs));
          }
        },
        maxRetries: 4,
        onDropped: (logs) => dropped.addAll(messagesOf(logs)),
      );
      final log = makeLogger(publisher);

      log.i('recovers');
      await publisher.flush().timeout(const Duration(seconds: 2));
      expect(attempts, 3, reason: 'two failures, then it got through');
      expect(handled, ['recovers']);

      attempts = 0;
      failuresLeft = 1000;
      log.i('undeliverable');
      await pumpUntil(() => dropped.isNotEmpty);

      expect(attempts, 5, reason: 'the success paid the whole budget back');
      expect(dropped, ['undeliverable']);

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: C1 (project review 2026-08-19[2])
    test('maxRetries of zero drops a handed-back batch at once', () async {
      var attempts = 0;
      final dropped = <String?>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) {
          attempts++;
          retry.addAll(logs);
        },
        maxRetries: 0,
        onDropped: (logs) => dropped.addAll(messagesOf(logs)),
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      await pumpUntil(() => dropped.isNotEmpty);

      expect(attempts, 1);
      expect(dropped, ['undeliverable']);

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: C1 (project review 2026-08-19[2]) — a flat delay spends
    // the whole budget in the first fraction of a second, which is no use
    // to a sink that is down for a while.
    test('the retry delay grows with each attempt', () async {
      final stamps = <int>[];
      final elapsed = Stopwatch()..start();
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) {
          stamps.add(elapsed.elapsedMilliseconds);
          retry.addAll(logs);
        },
        retryDelay: const Duration(milliseconds: 20),
        maxRetries: 3,
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      // A lower bound is exactly what this one tests, so it waits out a
      // window rather than polling — but the window is generous and the
      // assertion below is on the stamps, not on the window.
      await pumpUntil(() => stamps.length == 4);

      expect(stamps, hasLength(4));
      // A flat 20 ms would put the last attempt near 60 ms; 20/40/80 puts
      // it past 120. The margin is wide on purpose — this asserts growth,
      // not a schedule.
      expect(stamps.last, greaterThan(100));

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: coverage audit for the 2026-08-19[2] review — handing the
    // live retry buffer to `onDropped` instead of a copy survived as a
    // mutation. The handler legitimately still holds that buffer: it is the
    // list it was given, and an asynchronous one may write to it after its
    // future has completed. Both drop paths hand a list out, so both are
    // run here — the first version of this test covered only the budget
    // one, and the mutation on the close path went on surviving.
    for (final path in ['a spent budget', 'a close']) {
      test('onDropped receives a copy of the retry buffer after $path',
          () async {
        final atClose = path == 'a close';
        List<Log>? handlerBuffer;
        List<Log>? reported;
        final publisher = AsyncPublisherWithBuffer<Log>(
          (logs, retry) {
            handlerBuffer = retry;
            retry.addAll(logs);
          },
          maxRetries: atClose ? 100 : 0,
          retryDelay: atClose ? const Duration(milliseconds: 5) : Duration.zero,
          onDropped: (logs) => reported ??= logs,
        );
        final log = makeLogger(publisher);

        log.i('undeliverable');
        await pumpUntil(() => reported != null);
        await publisher.close().timeout(const Duration(seconds: 2));

        expect(reported, hasLength(1));

        handlerBuffer!.clear();

        expect(reported, hasLength(1), reason: 'onDropped must own its list');
      });
    }

    // Regression: M9 (project review 2026-08-19[2]) — `format` and `output`
    // both receive the retry buffer, so what comes back is "what format
    // handed back" followed by "what output handed back". When they hand
    // back different parts of the batch, that is not publish order, and the
    // queue put it into the next batch exactly as it found it. Order is a
    // promise this publisher makes, and it was broken on the recovery path,
    // where it is least likely to be noticed.
    test('a partial retry keeps the batch in publish order', () async {
      final batches = <List<String?>>[];
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) {
          batches.add(messagesOf(logs));
          if (batches.length == 1) {
            // The third log fails to format; the rest goes on to output.
            retry.add(logs[2]);
          }

          return 'out';
        },
        output: (out, logs, retry) {
          if (batches.length == 1) {
            // ...where the sink then rejects everything it was given.
            retry.addAll(logs);
          }
        },
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two')
        ..i('three')
        ..i('four');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(batches, hasLength(2));
      expect(
        batches[1],
        orderedEquals(['one', 'two', 'three', 'four']),
        reason: 'the retry must not reorder the batch',
      );

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: L8 (project review 2026-08-19[2]) — `output` was called
    // even when `format` had handed the whole batch back, with an empty list
    // of logs and whatever payload `format` had built. For a network or file
    // sink that is an empty request on every retry.
    test('output is skipped when format hands the whole batch back', () async {
      var outputs = 0;
      var formats = 0;
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) {
          formats++;
          if (formats <= 2) {
            retry.addAll(logs);
          }

          return 'payload';
        },
        output: (out, logs, retry) => outputs++,
      );
      final log = makeLogger(publisher);

      log.i('undeliverable');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(formats, 3, reason: 'two refusals, then it went through');
      expect(outputs, 1, reason: 'only the attempt that kept something');

      await publisher.close().timeout(const Duration(seconds: 2));
    });

    // Regression: L9 (project review 2026-08-19[2]) — the queue is built
    // lazily, on the first `publish`, and it captured `Zone.current` there.
    // A logger is usually built at the top level while the first log happens
    // inside some request scope, so every later handler error was reported
    // into whichever scope happened to log first. The unbuffered family
    // pins its zone at construction and says so in a comment; this one did
    // the opposite by accident.
    test('handler errors go to the zone that built the publisher', () async {
      final built = <Object>[];
      final published = <Object>[];
      late final AsyncPublisherWithBuffer<Log> publisher;

      runZonedGuarded(
        () => publisher = AsyncPublisherWithBuffer<Log>((logs, retry) {
          throw StateError('sink down');
        }),
        (error, stackTrace) => built.add(error),
      );

      Future<void>? closing;
      runZonedGuarded(
        () {
          makeLogger(publisher).i('first ever log');
          closing = publisher.close();
        },
        (error, stackTrace) => published.add(error),
      );
      await closing?.timeout(const Duration(seconds: 2));

      expect(built, hasLength(1));
      expect(published, isEmpty, reason: 'the first publisher does not own it');
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
      expect(() => log.i('b'), throwsPublisherClosed);
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

    // Regression: H4 (project review 2026-08-16[4]) — the synchronous arm of
    // the format switch was never executed by any test, so a regression there
    // would have silently dropped every log.
    test('a synchronous format still reaches output', () async {
      final outputs = <String>[];
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) => messagesOf(logs).join(','),
        output: (out, logs, retry) => outputs.add(out),
      );
      final log = makeLogger(publisher);

      log.i('a');
      log.i('b');
      await publisher.flush();

      expect(outputs, ['a,b']);
    });

    // Regression: H3 (project review 2026-08-16[4]) — a throwing format left
    // no point at which the caller could hand the batch back, so the batch
    // was dropped silently.
    test('a synchronously throwing format retries the whole batch', () async {
      final outputs = <String>[];
      final errors = <Object>[];
      var first = true;
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) {
          if (first) {
            first = false;
            throw StateError('format boom');
          }

          return messagesOf(logs).join(',');
        },
        output: (out, logs, retry) => outputs.add(out),
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = makeLogger(publisher);

      log.i('a');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(errors.single, isStateError);
      expect(outputs, ['a']);
    });

    // Regression: H3
    test('a format whose future fails retries the whole batch', () async {
      final outputs = <String>[];
      final errors = <Object>[];
      var first = true;
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) async {
          await Future<void>.delayed(Duration.zero);
          if (first) {
            first = false;
            throw StateError('format boom');
          }

          return messagesOf(logs).join(',');
        },
        output: (out, logs, retry) => outputs.add(out),
        onError: (error, stackTrace) => errors.add(error),
      );
      final log = makeLogger(publisher);

      log.i('a');
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(errors.single, isStateError);
      expect(outputs, ['a']);
    });

    // Regression: M9 (project review 2026-08-16[4]) — the remaining logs were
    // computed as a set difference, so handing one copy of a duplicated log
    // back withdrew the other copy from output as well.
    test('retrying one copy of a duplicated log keeps the other', () async {
      late Log sample;
      makeLogger(CustomLogPublisher<Log>((log) => sample = log)).i('dup');

      final batches = <List<String?>>[];
      var first = true;
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) {
          if (first) {
            first = false;
            retry.add(logs.first);
          }

          return 'batch';
        },
        output: (out, remaining, retry) => batches.add(messagesOf(remaining)),
      )
        ..publish(sample)
        ..publish(sample);

      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(batches, [
        ['dup'],
        ['dup'],
      ]);
    });

    // Regression: M4 (project review 2026-08-17[1]) — the retry Timer was not
    // kept anywhere, so close() had to wait out the whole retryDelay before it
    // could drain, and the entries it waited for were dropped afterwards
    // anyway.
    test('close does not wait out a pending retryDelay', () async {
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) => retry.addAll(logs),
        retryDelay: const Duration(seconds: 5),
      );
      final log = makeLogger(publisher);

      log.i('stuck');
      // Let the first attempt run and arm the retry timer.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final stopwatch = Stopwatch()..start();
      await publisher.close().timeout(const Duration(seconds: 2));
      stopwatch.stop();

      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 1)),
        reason: 'close must cancel the pending retry, not sleep through it',
      );
    });

    // Regression: M6 (project review 2026-08-17[1]) — entries handed back after
    // close() were dropped with no error, no callback and no counter.
    test('onDropped receives the entries dropped at close', () async {
      final dropped = <List<String?>>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) => retry.addAll(logs),
        onDropped: (logs) => dropped.add(messagesOf(logs)),
        retryDelay: const Duration(milliseconds: 5),
      );
      final log = makeLogger(publisher);

      log.i('lost');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await publisher.close().timeout(const Duration(seconds: 2));

      expect(dropped, isNotEmpty);
      expect(dropped.expand((batch) => batch), contains('lost'));
    });

    test('a throwing onDropped does not derail the shutdown', () async {
      final zoneErrors = <Object>[];
      late Future<void> closeFuture;
      runZonedGuarded(
        () {
          final publisher = AsyncPublisherWithBuffer<Log>(
            (logs, retry) => retry.addAll(logs),
            onDropped: (logs) => throw StateError('handler boom'),
            retryDelay: const Duration(milliseconds: 5),
          );
          makeLogger(publisher).i('lost');
          closeFuture = Future<void>.delayed(
            const Duration(milliseconds: 20),
            publisher.close,
          );
        },
        (error, stackTrace) => zoneErrors.add(error),
      );
      await closeFuture.timeout(const Duration(seconds: 2));

      expect(zoneErrors.single, isA<StateError>());
    });

    // Regression: L9 (project review 2026-08-20[1]) — the buffered twin of
    // the identity check: the same future, not merely one that completes at
    // the same time.
    test('flush during a close hands back that very future', () async {
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {
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

    // Regression: M5 (project review 2026-08-17[1]) — isClosed flips when
    // close() is *called*, so flush() short-circuited to an already-completed
    // future while the queue was still in flight: a false all-clear.
    test('flush during a close waits for the close', () async {
      final handled = <String?>[];
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        handled.addAll(messagesOf(logs));
      });
      final log = makeLogger(publisher);

      log.i('in flight');
      final closeFuture = publisher.close();
      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(
        handled,
        ['in flight'],
        reason: 'flush must not report an empty queue mid-shutdown',
      );
      await closeFuture;
    });

    // Regression: H5 (project review 2026-08-17[1]) — pins the documented
    // asymmetry with `format`: `output` runs after the sink may already have
    // taken part of the batch, so a throw does not retry wholesale. Only what
    // `output` handed back survives. This is a contract, not an accident: if it
    // ever changes, this test must change with it.
    test('a throwing output keeps only what it handed back', () async {
      final delivered = <String?>[];
      final errors = <Object>[];
      var first = true;
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) => 'batch',
        output: (out, logs, retry) {
          if (first) {
            first = false;
            retry.add(logs.first);
            throw StateError('output boom');
          }

          delivered.addAll(messagesOf(logs));
        },
        onError: (error, stackTrace) => errors.add(error),
        retryDelay: const Duration(milliseconds: 5),
      );
      final log = makeLogger(publisher);

      log.i('kept');
      log.i('dropped');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await publisher.close().timeout(const Duration(seconds: 2));

      expect(errors.single, isStateError);
      expect(delivered, ['kept']);
    });

    // Regression: M19 (project review 2026-08-17[1]) — the test above publishes
    // one object twice, so identity and value equality behave alike in it and
    // it cannot fail if the identity map is replaced by a plain one. This case
    // uses two distinct logs that compare equal, which only identity separates.
    // Regression: M8 (project review 2026-08-20[1]) — `_inPublishOrder`
    // counts the handed-back entries in an identity map, and the sibling
    // counter in `remainingEntries` had a test for exactly that while this
    // one had none. With a value map two distinct logs that compare equal
    // collapse into one key, and the batch that goes back into the queue
    // holds the entry that was *not* handed back.
    test('the retried batch keeps the entries the handler handed back',
        () async {
      final levelLogger = Logger('test')[Levels.info];
      final a = EqLog(levelLogger, 'dup');
      final other = EqLog(levelLogger, 'other');
      final b = EqLog(levelLogger, 'dup');
      expect(a == b, isTrue, reason: 'the fixture must have value equality');
      expect(identical(a, b), isFalse);

      final batches = <List<EqLog>>[];
      final publisher = AsyncPublisherWithBuffer<EqLog>((logs, retry) {
        batches.add(List<EqLog>.of(logs));
        if (batches.length == 1) {
          // Handed back out of publish order, so the reordering runs.
          retry
            ..add(logs[2])
            ..add(logs[1]);
        }
      })
        ..publish(a)
        ..publish(other)
        ..publish(b);

      await publisher.flush().timeout(const Duration(seconds: 2));
      await publisher.close().timeout(const Duration(seconds: 2));

      expect(batches, hasLength(2), reason: 'one retry');
      String name(EqLog log) {
        if (identical(log, a)) {
          return 'a';
        }

        return identical(log, other) ? 'other' : 'b';
      }

      expect(
        batches[1].map(name),
        ['other', 'b'],
        reason: 'the entries handed back, in publish order',
      );
    });

    // Regression: M8 — `retryWholeBatch` clears the retry buffer before
    // refilling it. Without the clear, a `format` that put part of the
    // batch back and only then threw left those entries in the buffer and
    // the whole batch on top of them: the sink received them twice, which
    // in production is indistinguishable from a retransmission.
    test('a format that hands back and then throws does not duplicate',
        () async {
      final delivered = <String?>[];
      var first = true;
      final publisher = AsyncFormatterWithBuffer<Log, String>(
        format: (logs, retry) {
          if (first) {
            first = false;
            retry.add(logs[0]);

            throw StateError('format failed after handing one back');
          }

          return 'batch';
        },
        output: (out, remaining, retry) =>
            delivered.addAll(messagesOf(remaining)),
        onError: (error, stackTrace) {},
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two');

      await publisher.flush().timeout(const Duration(seconds: 2));
      await publisher.close().timeout(const Duration(seconds: 2));

      expect(delivered, ['one', 'two'], reason: 'each log exactly once');
    });

    test('retrying one of two equal but distinct logs keeps both', () async {
      final levelLogger = Logger('test')[Levels.info];
      final a = EqLog(levelLogger, 'dup');
      final b = EqLog(levelLogger, 'dup');
      expect(a == b, isTrue, reason: 'the fixture must have value equality');
      expect(identical(a, b), isFalse);

      final delivered = <EqLog>[];
      var first = true;
      final publisher = AsyncFormatterWithBuffer<EqLog, String>(
        format: (logs, retry) {
          if (first) {
            first = false;
            retry.add(logs[1]);
          }

          return 'batch';
        },
        output: (out, remaining, retry) => delivered.addAll(remaining),
      )
        ..publish(a)
        ..publish(b);

      await publisher.flush().timeout(const Duration(seconds: 2));

      expect(
        delivered.map((log) => identical(log, a) ? 'a' : 'b').toList(),
        ['a', 'b'],
        reason: 'each distinct log must reach output exactly once',
      );
    });
  });
}
