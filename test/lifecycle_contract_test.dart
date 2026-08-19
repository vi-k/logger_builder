import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

/// One publisher under test, reduced to what the shared lifecycle contract
/// needs: somewhere to publish, the two operations, and what the sink has
/// actually seen.
///
/// The eight asynchronous classes are near-copies of each other, and so are
/// their tests — which is how a contract came to hold in two of them and
/// not in the other six. Naming the contract once and running it over every
/// class is the cheaper half of fixing that.
final class _Subject {
  final CustomLogPublisher<Log> sink;
  final Flushable flushable;
  final Closable closable;
  final List<String?> handled;

  _Subject({
    required this.sink,
    required this.flushable,
    required this.closable,
    required this.handled,
  });
}

/// Long enough that the drain cannot finish inside the microtask a broken
/// `flush()` completes on, short enough to keep the suite fast.
Future<void> _slowly() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

final Map<String, _Subject Function()> _families = {
  'AsyncPublisher': () {
    final handled = <String?>[];
    final publisher = AsyncPublisher<Log>((log) async {
      await _slowly();
      handled.add(log.message);
    });

    return _Subject(
      sink: publisher,
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'AsyncFormatter': () {
    final handled = <String?>[];
    final publisher = AsyncFormatter<Log, String?>(
      format: (log) async {
        await _slowly();

        return log.message;
      },
      output: handled.add,
    );

    return _Subject(
      sink: publisher,
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'AsyncPublisherWithParam': () {
    final handled = <String?>[];
    final publisher = AsyncPublisherWithParam<String, Log>((param, log) async {
      await _slowly();
      handled.add(log.message);
    });

    return _Subject(
      sink: publisher.withParam('p'),
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'AsyncFormatterWithParam': () {
    final handled = <String?>[];
    final publisher = AsyncFormatterWithParam<String, Log, String?>(
      format: (param, log) async {
        await _slowly();

        return log.message;
      },
      output: (param, out) => handled.add(out),
    );

    return _Subject(
      sink: publisher.withParam('p'),
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'AsyncPublisherWithBuffer': () {
    final handled = <String?>[];
    final publisher = AsyncPublisherWithBuffer<Log>((logs, retryBuffer) async {
      await _slowly();
      handled.addAll(logs.map((log) => log.message));
    });

    return _Subject(
      sink: publisher,
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'AsyncFormatterWithBuffer': () {
    final handled = <String?>[];
    final publisher = AsyncFormatterWithBuffer<Log, List<String?>>(
      format: (logs, retryBuffer) async {
        await _slowly();

        return logs.map((log) => log.message).toList();
      },
      output: (out, logs, retryBuffer) => handled.addAll(out),
    );

    return _Subject(
      sink: publisher,
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'AsyncPublisherWithBufferAndParam': () {
    final handled = <String?>[];
    final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
      (entries, retryBuffer) async {
        await _slowly();
        handled.addAll(entries.map((entry) => entry.$2.message));
      },
    );

    return _Subject(
      sink: publisher.withParam('p'),
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'AsyncFormatterWithBufferAndParam': () {
    final handled = <String?>[];
    final publisher =
        AsyncFormatterWithBufferAndParam<String, Log, List<String?>>(
      format: (entries, retryBuffer) async {
        await _slowly();

        return entries.map((entry) => entry.$2.message).toList();
      },
      output: (out, entries, retryBuffer) => handled.addAll(out),
    );

    return _Subject(
      sink: publisher.withParam('p'),
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'MultiPublisher': () {
    final handled = <String?>[];
    final inner = AsyncPublisher<Log>((log) async {
      await _slowly();
      handled.add(log.message);
    });
    final publisher = MultiPublisher<Log>([inner]);

    return _Subject(
      sink: publisher,
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
  'TransformPublisher': () {
    final handled = <String?>[];
    final inner = AsyncPublisher<Log>((log) async {
      await _slowly();
      handled.add(log.message);
    });
    final publisher = TransformPublisher<Log>(inner, transformer: (log) => log);

    return _Subject(
      sink: publisher,
      flushable: publisher,
      closable: publisher,
      handled: handled,
    );
  },
};

void main() {
  group('the Flushable/Closable contract, over every publisher', () {
    // Regression: M1 (project review 2026-08-19[2]). `isClosed` flips when
    // `close()` is *called*, not when it finishes, so `flush()` reported an
    // empty queue while the logs were still in flight. `BufferedPipeline`
    // was fixed for this once and says so in a comment; the other six
    // classes kept the old behaviour, and `MultiPublisher` demoted a
    // correct wrapped publisher to it.
    for (final family in _families.entries) {
      test('${family.key}: flush during a close waits for the close', () async {
        final subject = family.value();
        makeLogger(subject.sink).i('in flight');

        final closing = subject.closable.close();
        await subject.flushable.flush().timeout(const Duration(seconds: 2));

        expect(
          subject.handled,
          ['in flight'],
          reason: 'flush must not report an empty queue mid-shutdown',
        );
        await closing;
      });
    }

    for (final family in _families.entries) {
      test('${family.key}: flush after a finished close completes', () async {
        final subject = family.value();
        makeLogger(subject.sink).i('before the close');

        await subject.closable.close();

        await subject.flushable.flush().timeout(const Duration(seconds: 2));
        expect(subject.handled, ['before the close']);
      });
    }

    for (final family in _families.entries) {
      test('${family.key}: close drains what was already accepted', () async {
        final subject = family.value();
        makeLogger(subject.sink).i('accepted');

        await subject.closable.close().timeout(const Duration(seconds: 2));

        expect(subject.handled, ['accepted']);
      });
    }
  });
}

Logger makeLogger(CustomLogPublisher<Log> publisher) => Logger('test')
  ..level = Levels.all
  ..publisher = publisher;
