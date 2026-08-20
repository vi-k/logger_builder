import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/wait.dart';

Logger makeLogger(CustomLogPublisher<Log> publisher) => Logger('test')
  ..level = Levels.all
  ..publisher = publisher;

/// One publisher under test, reduced to what the bound needs: somewhere to
/// publish, what closes it, the gate that keeps its handler busy, and what
/// its `onDropped` has seen.
///
/// The eight asynchronous classes are near-copies of each other, and this
/// project has already watched a contract hold in two of them and not in the
/// other six. Naming the contract once and running it over every class is
/// the cheaper half of not repeating that.
typedef _Case = ({
  CustomLogPublisher<Log> sink,
  Closable closable,
  Completer<void> gate,
  List<String?> dropped,
});

final Map<String, _Case Function()> _bounded = {
  'AsyncPublisher': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisher<Log>(
      (log) => gate.future,
      maxQueueSize: 1,
      onDropped: (log) => dropped.add(log.message),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
  'AsyncFormatter': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatter<Log, String?>(
      format: (log) => log.message,
      output: (out) => gate.future,
      maxQueueSize: 1,
      onDropped: (log) => dropped.add(log.message),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
  'AsyncPublisherWithParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisherWithParam<String, Log>(
      (param, log) => gate.future,
      maxQueueSize: 1,
      onDropped: (param, log) => dropped.add(log.message),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
  'AsyncFormatterWithParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatterWithParam<String, Log, String?>(
      format: (param, log) => log.message,
      output: (param, out) => gate.future,
      maxQueueSize: 1,
      onDropped: (param, log) => dropped.add(log.message),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
  'AsyncPublisherWithBuffer': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisherWithBuffer<Log>(
      (logs, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
  'AsyncFormatterWithBuffer': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatterWithBuffer<Log, int>(
      format: (logs, retryBuffer) => logs.length,
      output: (out, logs, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
  'AsyncPublisherWithBufferAndParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
      (entries, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (entries) =>
          dropped.addAll(entries.map((entry) => entry.$2.message)),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
  'AsyncFormatterWithBufferAndParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatterWithBufferAndParam<String, Log, int>(
      format: (entries, retryBuffer) => entries.length,
      output: (out, entries, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (entries) =>
          dropped.addAll(entries.map((entry) => entry.$2.message)),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped,
    );
  },
};

/// Every one of the eight built the way the README shows it — with no
/// `maxQueueSize` at all — so the default can be read off the object.
final Map<String, ({int? bound, Closable closable}) Function()> _defaults = {
  'AsyncPublisher': () {
    final publisher = AsyncPublisher<Log>((log) {});

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
  'AsyncFormatter': () {
    final publisher = AsyncFormatter<Log, String?>(
      format: (log) => log.message,
      output: (out) {},
    );

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
  'AsyncPublisherWithParam': () {
    final publisher = AsyncPublisherWithParam<String, Log>((param, log) {});

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
  'AsyncFormatterWithParam': () {
    final publisher = AsyncFormatterWithParam<String, Log, String?>(
      format: (param, log) => log.message,
      output: (param, out) {},
    );

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
  'AsyncPublisherWithBuffer': () {
    final publisher = AsyncPublisherWithBuffer<Log>((logs, retryBuffer) {});

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
  'AsyncFormatterWithBuffer': () {
    final publisher = AsyncFormatterWithBuffer<Log, int>(
      format: (logs, retryBuffer) => logs.length,
      output: (out, logs, retryBuffer) {},
    );

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
  'AsyncPublisherWithBufferAndParam': () {
    final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
      (entries, retryBuffer) {},
    );

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
  'AsyncFormatterWithBufferAndParam': () {
    final publisher = AsyncFormatterWithBufferAndParam<String, Log, int>(
      format: (entries, retryBuffer) => entries.length,
      output: (out, entries, retryBuffer) {},
    );

    return (bound: publisher.maxQueueSize, closable: publisher);
  },
};

void main() {
  group('AsyncPublisher', () {
    test('a full queue refuses the incoming log', () async {
      final gate = Completer<void>();
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) => gate.future,
        maxQueueSize: 2,
        onDropped: (log) => dropped.add(log.message),
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['three']);

      gate.complete();
      await publisher.close();
    });

    test('acceptance resumes once the queue drains', () async {
      final gate = Completer<void>();
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) async {
          await gate.future;
          handled.add(log.message);
        },
        maxQueueSize: 2,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher)
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['three']);

      gate.complete();
      await publisher.flush();
      expect(handled, ['one', 'two']);

      log.i('four');
      await publisher.flush();

      expect(handled, ['one', 'two', 'four']);
      expect(dropped, ['three']);
      await publisher.close();
    });

    test('maxQueueSize: null keeps the queue unbounded', () async {
      final gate = Completer<void>();
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) async {
          await gate.future;
          handled.add(log.message);
        },
        maxQueueSize: null,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher);
      for (var i = 0; i < 50; i++) {
        log.i('$i');
      }

      expect(dropped, isEmpty);

      gate.complete();
      await publisher.close();

      expect(handled, hasLength(50));
    });

    test('maxQueueSize: 0 is a programming error', () {
      expect(
        () => AsyncPublisher<Log>((_) {}, maxQueueSize: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('AsyncPublisherWithParam', () {
    test('a full queue refuses the incoming entry with its param', () async {
      final gate = Completer<void>();
      final dropped = <String>[];
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) => gate.future,
        maxQueueSize: 2,
        onDropped: (param, log) => dropped.add('$param:${log.message}'),
      );
      makeLogger(publisher.withParam('file'))
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['file:three']);

      gate.complete();
      await publisher.close();
    });
  });

  group('AsyncPublisherWithBuffer', () {
    test('a full buffer refuses the incoming log', () async {
      final gate = Completer<void>();
      final dropped = <String?>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retryBuffer) => gate.future,
        maxQueueSize: 2,
        onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['three']);

      gate.complete();
      await publisher.close();
    });

    test('a retried batch is not cut by the limit', () async {
      final handled = <String?>[];
      final dropped = <String?>[];
      var attempts = 0;
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retryBuffer) {
          attempts++;
          if (attempts == 1) {
            retryBuffer.addAll(logs);

            return;
          }
          handled.addAll(logs.map((log) => log.message));
        },
        maxQueueSize: 2,
        onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two');

      await pumpUntil(() => handled.length == 2);

      expect(handled, ['one', 'two']);
      expect(dropped, isEmpty);
      await publisher.close();
    });

    test('the count follows a batch that went back into the queue', () async {
      final gate = Completer<void>();
      final dropped = <String?>[];
      var attempts = 0;
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retryBuffer) {
          attempts++;
          if (attempts == 1) {
            retryBuffer.addAll(logs);

            return null;
          }

          return gate.future;
        },
        maxQueueSize: 2,
        onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
      );
      final log = makeLogger(publisher)
        ..i('one')
        ..i('two');

      // The retried batch is in flight again: two entries are still held,
      // so the queue is still full and a third log has nowhere to go.
      await pumpUntil(() => attempts == 2);
      log.i('three');

      expect(dropped, ['three']);

      gate.complete();
      await publisher.close();
    });
  });

  group('AsyncPublisherWithBufferAndParam', () {
    test('a full buffer refuses the incoming entry', () async {
      final gate = Completer<void>();
      final dropped = <String>[];
      final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
        (entries, retryBuffer) => gate.future,
        maxQueueSize: 2,
        onDropped: (entries) => dropped.addAll(
          entries.map((entry) => '${entry.$1}:${entry.$2.message}'),
        ),
      );
      makeLogger(publisher.withParam('db'))
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['db:three']);

      gate.complete();
      await publisher.close();
    });
  });
  group('every publisher refuses when full', () {
    for (final entry in _bounded.entries) {
      test(entry.key, () async {
        final subject = entry.value();
        makeLogger(subject.sink)
          ..i('one')
          ..i('two');

        expect(subject.dropped, ['two'], reason: entry.key);

        subject.gate.complete();
        await subject.closable.close();
      });
    }

    // Regression: M1 (project review 2026-08-20[1]) — this test used to
    // assert only that one error reached the zone. That is true in both
    // worlds: with the guard because it sent the error there, without one
    // because the error flew out of the logging call and the surrounding
    // runZonedGuarded caught it. Removing `guarded` around onDropped left
    // the test green. What the guard promises is that the logging call
    // *returns*, so that is what is asserted now.
    test('a throwing onDropped does not reach the logging call', () async {
      final gate = Completer<void>();
      final errors = <Object>[];
      Object? atCallSite;
      var returned = false;
      late final AsyncPublisher<Log> publisher;
      runZonedGuarded(
        () {
          publisher = AsyncPublisher<Log>(
            (log) => gate.future,
            maxQueueSize: 1,
            onDropped: (log) => throw StateError('boom'),
          );
          final log = makeLogger(publisher)..i('one');
          try {
            log.i('two');
            returned = true;
          } on Object catch (error) {
            atCallSite = error;
          }
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(atCallSite, isNull, reason: 'the guard keeps it off the call');
      expect(returned, isTrue, reason: 'the logging call returned normally');
      expect(errors, hasLength(1), reason: 'and the error went to the zone');

      gate.complete();
      await publisher.close();
    });

    // Regression: M1 — the buffered twin of the test above. The buffered
    // family had no test for this path at all: its throwing-onDropped test
    // covers the shutdown, where both worlds end up in the zone anyway
    // (the tick loop's last-resort guard puts them there), so it cannot
    // tell a guarded callback from an unguarded one. The full queue can:
    // there the callback runs on the stack of the logging call.
    test('a throwing onDropped does not reach the logging call, buffered',
        () async {
      final gate = Completer<void>();
      final errors = <Object>[];
      Object? atCallSite;
      var returned = false;
      late final AsyncPublisherWithBuffer<Log> publisher;
      runZonedGuarded(
        () {
          publisher = AsyncPublisherWithBuffer<Log>(
            (logs, retryBuffer) => gate.future,
            maxQueueSize: 1,
            onDropped: (logs) => throw StateError('boom'),
          );
          final log = makeLogger(publisher)..i('one');
          try {
            log.i('two');
            returned = true;
          } on Object catch (error) {
            atCallSite = error;
          }
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(atCallSite, isNull, reason: 'the guard keeps it off the call');
      expect(returned, isTrue, reason: 'the logging call returned normally');
      expect(errors, hasLength(1), reason: 'and the error went to the zone');

      gate.complete();
      await publisher.close();
    });

    test('a handler that keeps up never trips the limit', () {
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) => handled.add(log.message),
        sync: true,
        maxQueueSize: 1,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher);
      for (var i = 0; i < 100; i++) {
        log.i('$i');
      }

      expect(handled, hasLength(100));
      expect(dropped, isEmpty);
    });

    test('flush and close still complete while logs are dropped', () async {
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) async {
          await Future<void>.delayed(Duration.zero);
          handled.add(log.message);
        },
        maxQueueSize: 3,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher);
      for (var i = 0; i < 20; i++) {
        log.i('$i');
      }

      expect(dropped, isNotEmpty);

      await publisher.flush();
      await publisher.close();

      expect(handled.length + dropped.length, 20);
      expect(publisher.isClosed, isTrue);
    });
  });
  group('the default bound', () {
    // 100 000 accepted and not yet handled. The number is written into the
    // dartdoc of both bases and into both READMEs, which makes it a promise
    // rather than an implementation detail — and one nothing else here
    // would notice drifting.
    for (final entry in _defaults.entries) {
      test(entry.key, () async {
        final subject = entry.value();

        expect(subject.bound, 100000, reason: entry.key);

        await subject.closable.close();
      });
    }
  });
  group('the default onDropped', () {
    /// Captures what the package prints: `print` goes through the current
    /// zone, so a test can hold it without touching the package.
    Future<List<String>> printedDuring(Future<void> Function() body) async {
      final printed = <String>[];
      await runZoned(
        body,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );

      return printed;
    }

    test('an unset onDropped still says logs are being lost', () async {
      final printed = await printedDuring(() async {
        final gate = Completer<void>();
        final publisher = AsyncPublisher<Log>(
          (log) => gate.future,
          maxQueueSize: 1,
        );
        makeLogger(publisher)
          ..i('one')
          ..i('two');

        gate.complete();
        await publisher.close();
      });

      expect(printed, hasLength(1));
      expect(printed.single, contains('logger_builder'));
      expect(printed.single, contains('queue full'));
      expect(printed.single, contains('onDropped'));
    });

    test('an onDropped that was set keeps the package quiet', () async {
      final dropped = <String?>[];
      final printed = await printedDuring(() async {
        final gate = Completer<void>();
        final publisher = AsyncPublisher<Log>(
          (log) => gate.future,
          maxQueueSize: 1,
          onDropped: (log) => dropped.add(log.message),
        );
        makeLogger(publisher)
          ..i('one')
          ..i('two');

        gate.complete();
        await publisher.close();
      });

      expect(dropped, ['two']);
      expect(printed, isEmpty);
    });

    test('close counts the losses the window swallowed', () async {
      final printed = await printedDuring(() async {
        final gate = Completer<void>();
        final publisher = AsyncPublisher<Log>(
          (log) => gate.future,
          maxQueueSize: 1,
        );
        final log = makeLogger(publisher);
        for (var i = 0; i < 20; i++) {
          log.i('$i');
        }

        gate.complete();
        await publisher.close();
      });

      expect(printed, hasLength(2), reason: 'the opening line and the count');
      expect(printed.last, contains('18 log events'));
    });

    test('a buffered close counts what its window swallowed', () async {
      final printed = await printedDuring(() async {
        final gate = Completer<void>();
        final publisher = AsyncPublisherWithBuffer<Log>(
          (logs, retryBuffer) => gate.future,
          maxQueueSize: 1,
        );
        final log = makeLogger(publisher);
        for (var i = 0; i < 20; i++) {
          log.i('$i');
        }

        gate.complete();
        await publisher.close();
      });

      expect(printed, hasLength(2), reason: 'the opening line and the count');
      expect(printed.last, contains('18 log events'));
    });

    // Regression: H2 (project review 2026-08-20[1]) — redirecting `print`
    // into a file or a crash reporter is an everyday Dart and Flutter
    // pattern, and such a sink can fail. The default reporter called it
    // unguarded, so a dropped log became a throw at the logging call site
    // and an error out of close(): the mechanism that exists to make a lost
    // log audible was killing the application instead.
    test('a throwing print derails neither publishing nor close', () async {
      final zoneErrors = <Object>[];
      final done = Completer<void>();
      Object? publishError;
      Object? closeError;

      unawaited(
        runZonedGuarded(
          () async {
            final gate = Completer<void>();
            final publisher = AsyncPublisher<Log>(
              (log) => gate.future,
              maxQueueSize: 1,
            );
            final log = makeLogger(publisher);
            try {
              for (var i = 0; i < 20; i++) {
                log.i('$i');
              }
            } on Object catch (error) {
              publishError = error;
            }

            gate.complete();
            try {
              await publisher.close();
            } on Object catch (error) {
              closeError = error;
            }
            done.complete();
          },
          (error, stackTrace) => zoneErrors.add(error),
          zoneSpecification: ZoneSpecification(
            print: (self, parent, zone, line) =>
                throw StateError('print sink is closed'),
          ),
        ),
      );

      await done.future.timeout(const Duration(seconds: 5));

      expect(publishError, isNull, reason: 'a lost log is not a broken call');
      expect(closeError, isNull, reason: 'nor a broken shutdown');
      expect(
        zoneErrors,
        hasLength(2),
        reason: "the sink's own errors go to the zone: opening and count",
      );
    });

    test('a buffered publisher speaks for its own losses too', () async {
      final printed = await printedDuring(() async {
        final gate = Completer<void>();
        final publisher = AsyncPublisherWithBuffer<Log>(
          (logs, retryBuffer) => gate.future,
          maxQueueSize: 1,
        );
        makeLogger(publisher)
          ..i('one')
          ..i('two');

        gate.complete();
        await publisher.close();
      });

      expect(printed, hasLength(1));
      expect(printed.single, contains('queue full'));
    });
  });
}
