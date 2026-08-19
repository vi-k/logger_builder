import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:meta/meta.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/matchers.dart';

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
    test('a permanently retrying handler does not starve the event loop',
        () async {
      var attempts = 0;
      final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) {
        attempts++;
        retry.addAll(logs);
      });
      final log = makeLogger(publisher);

      log.i('undeliverable');
      // A timer at all is the assertion: while the retries were a microtask
      // loop, this delay never completed and the test hung instead.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(attempts, greaterThan(1), reason: 'the batch should be retried');

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
      await Future<void>.delayed(const Duration(milliseconds: 50));

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
      await Future<void>.delayed(const Duration(milliseconds: 30));

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
      await Future<void>.delayed(const Duration(milliseconds: 20));

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
      await Future<void>.delayed(const Duration(milliseconds: 400));

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
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await publisher.close().timeout(const Duration(seconds: 2));

        expect(reported, hasLength(1));

        handlerBuffer!.clear();

        expect(reported, hasLength(1), reason: 'onDropped must own its list');
      });
    }

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
