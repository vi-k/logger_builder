import 'dart:async';

import 'package:logger_builder/src/async_publishers/internal/dropped_reporter.dart';
import 'package:test/test.dart';

/// A clock the test moves by hand: the reporter must not wait for real time
/// to be checked, and a test that sleeps five seconds is a test nobody runs.
final class _Clock {
  Duration now = Duration.zero;

  Duration call() => now;
}

void main() {
  late List<String> printed;
  late _Clock clock;
  late DroppedReporter reporter;

  setUp(() {
    printed = <String>[];
    clock = _Clock();
    reporter = DroppedReporter(
      sink: printed.add,
      now: clock.call,
      cap: const Duration(seconds: 20),
    );
  });

  test('the first loss speaks at once, and says what to do about it', () {
    reporter.record(1, DropCause.queueFull);

    expect(printed, hasLength(1));
    expect(printed.single, contains('logger_builder'));
    expect(printed.single, contains('queue full'));
    expect(printed.single, contains('onDropped'));
  });

  test('losses inside the window are silent', () {
    reporter.record(1, DropCause.queueFull);
    clock.now = const Duration(seconds: 4);
    reporter.record(100, DropCause.queueFull);

    expect(printed, hasLength(1));
  });

  test('the window closes with a count of what it swallowed', () {
    reporter.record(1, DropCause.queueFull);
    clock.now = const Duration(seconds: 4);
    reporter.record(100, DropCause.queueFull);
    clock.now = const Duration(seconds: 5);
    reporter.record(1, DropCause.queueFull);

    expect(printed, hasLength(2));
    expect(printed.last, contains('101'));
    expect(printed.last, contains('5.0s'));
  });

  test('the window doubles while the storm lasts, up to the cap', () {
    final windows = <Duration>[];
    var at = Duration.zero;
    for (var i = 0; i < 6; i++) {
      reporter.record(1, DropCause.queueFull);
      final before = printed.length;
      // Walk forward a second at a time until the reporter speaks again.
      while (printed.length == before) {
        at += const Duration(seconds: 1);
        clock.now = at;
        reporter.record(1, DropCause.queueFull);
      }
      windows.add(at);
    }

    expect(
      [
        windows[1] - windows[0],
        windows[2] - windows[1],
        windows[3] - windows[2],
        windows[4] - windows[3],
      ],
      [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
        const Duration(seconds: 20),
        const Duration(seconds: 20),
      ],
    );
  });

  test('a quiet spell resets the window to its base', () {
    reporter.record(1, DropCause.queueFull);
    clock.now = const Duration(seconds: 5);
    reporter.record(1, DropCause.queueFull);
    expect(printed, hasLength(2));

    // Two windows without a loss: the storm is over.
    clock.now = const Duration(seconds: 60);
    reporter.record(1, DropCause.queueFull);
    expect(printed, hasLength(3));

    clock.now = const Duration(seconds: 65);
    reporter.record(1, DropCause.queueFull);

    expect(printed, hasLength(4), reason: 'the base window is five seconds');
  });

  test('flush speaks the remainder and stays quiet when there is none', () {
    reporter.record(1, DropCause.queueFull);
    clock.now = const Duration(seconds: 1);
    reporter.record(7, DropCause.retriesSpent);

    expect(printed, hasLength(1));

    reporter.flush();

    expect(printed, hasLength(2));
    expect(printed.last, contains('7'));
    expect(printed.last, contains('retry budget'));

    reporter.flush();

    expect(printed, hasLength(2), reason: 'nothing left to report');
  });

  // Regression: H2 (project review 2026-08-20[1]) — the sink was called
  // bare while the user's onDropped went through `guarded`, so a zone whose
  // `print` throws turned a lost log into a throw at the logging call site.
  // Worse, the throw jumped over `_reset`, leaving the window open forever:
  // every later loss spoke, and every later loss threw.
  test('a throwing sink neither escapes nor freezes the window', () {
    final zoneErrors = <Object>[];
    final printed = <String>[];
    final clock = _Clock();
    final reporter = DroppedReporter(
      sink: (message) {
        printed.add(message);

        throw StateError('print sink is closed');
      },
      now: clock.call,
    );

    runZonedGuarded(
      () {
        reporter.record(1, DropCause.queueFull);
        clock.now = const Duration(seconds: 1);
        reporter.record(1, DropCause.queueFull);
        clock.now = const Duration(seconds: 6);
        reporter.record(1, DropCause.queueFull);
        clock.now = const Duration(seconds: 7);
        reporter
          ..record(1, DropCause.queueFull)
          ..flush();
      },
      (error, stackTrace) => zoneErrors.add(error),
    );

    expect(
      printed,
      hasLength(3),
      reason: 'the opening line, the closing window, and the flush',
    );
    expect(zoneErrors, hasLength(3), reason: "the sink's own errors go there");
  });

  test('a window that saw several causes names them all', () {
    // The opening line answers for the cause that triggered it and clears
    // the set: a summary names the causes of the window it covers.
    reporter.record(1, DropCause.queueFull);
    clock.now = const Duration(seconds: 1);
    reporter
      ..record(1, DropCause.queueFull)
      ..record(1, DropCause.retriesSpent)
      ..record(1, DropCause.closed)
      ..flush();

    expect(printed.last, contains('queue full'));
    expect(printed.last, contains('retry budget'));
    expect(printed.last, contains('closed'));
  });
}
