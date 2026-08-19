import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';
import 'utils/wait.dart';

Logger makeLogger(CustomLogPublisher<Log> publisher) => Logger('test')
  ..level = Levels.all
  ..publisher = publisher;

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
}
