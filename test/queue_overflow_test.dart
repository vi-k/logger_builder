import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

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
}
