// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import 'report.dart';

/// Why an entry will never be delivered.
enum DropCause {
  queueFull('queue full'),
  retriesSpent('retry budget spent'),
  closed('closed while retrying');

  const DropCause(this.text);

  final String text;
}

/// What a publisher does about a lost entry when the user set no
/// `onDropped`: says so, and then says it rarely.
///
/// Silence was the old answer and it is the worse one — a sink that stops
/// draining takes the logs that would have told you about it. Speaking on
/// every loss is not an answer either: losses come in floods, and a flood of
/// notices is the same problem wearing a hat.
///
/// So: the first loss speaks at once (a short program that drops a hundred
/// logs and exits must still say something), and after that a window
/// swallows the rest and reports a count. The window doubles while the
/// storm lasts, up to [cap], and returns to [window] once two windows pass
/// without a loss.
///
/// There is no timer anywhere in here, on purpose. A pending timer is a live
/// root for the event loop — this package has already had a worker that
/// could not return from `main` because of one — and a dropped log must not
/// buy the process five more seconds of life. The clock is read when a loss
/// happens and at [flush]; between losses nothing runs.
///
/// [window], [cap], [sink] and [now] are parameters rather than constants so
/// that a test can drive them. They are not settings: this file is not
/// exported.
///
/// Not exported by the package.
final class DroppedReporter {
  final Duration window;
  final Duration cap;
  final void Function(String message) sink;
  final Duration Function() now;

  Duration _current;
  Duration _lastSpoke = Duration.zero;
  int _pending = 0;
  bool _spoke = false;
  final Set<DropCause> _causes = <DropCause>{};

  DroppedReporter({
    this.window = const Duration(seconds: 5),
    this.cap = const Duration(minutes: 1),
    this.sink = print,
    Duration Function()? now,
  })  : now = now ?? _monotonic(),
        _current = window;

  static Duration Function() _monotonic() {
    final watch = Stopwatch()..start();

    return () => watch.elapsed;
  }

  void record(int count, DropCause cause) {
    _pending += count;
    _causes.add(cause);

    final at = now();
    if (!_spoke) {
      _spoke = true;
      _say(_opening());
      _reset(at);

      return;
    }

    final since = at - _lastSpoke;
    if (since < _current) {
      return;
    }

    _say(_summary(since));
    // A gap of more than two windows is a new storm, not a continuing one:
    // the doubling exists to quieten an outage, not to stay quiet after it.
    _current = since >= _current * 2 ? window : _grown();
    _reset(at);
  }

  /// Says what the last window swallowed, if anything. Called when the
  /// publisher closes, so the final losses are not left uncounted.
  void flush() {
    if (_pending == 0) {
      return;
    }

    final at = now();
    _say(_summary(at - _lastSpoke));
    _reset(at);
  }

  /// Speaks, and survives a sink that does not want to listen.
  ///
  /// The default sink is `print`, and `print` belongs to the zone: an
  /// application is free to redirect it into a file, a socket or a crash
  /// reporter, and any of those can fail. A user's `onDropped` is already
  /// guarded for exactly that reason — leaving the default path bare would
  /// mean the loss of a log kills the application that never asked for
  /// a reporter in the first place. The error goes to the zone, and the
  /// window is reset either way: a sink that throws once tends to throw
  /// again, and a window left unclosed would speak on every later loss.
  void _say(String message) => guarded(() => sink(message));

  void _reset(Duration at) {
    _pending = 0;
    _causes.clear();
    _lastSpoke = at;
  }

  Duration _grown() {
    final doubled = _current * 2;

    return doubled > cap ? cap : doubled;
  }

  String _opening() =>
      'logger_builder: dropping log events (${_causeText()}). Set onDropped '
      'to handle them, or onDropped: (_) {} to silence this; further losses '
      'are reported at most once every ${window.inSeconds}s.';

  String _summary(Duration since) {
    final seconds = (since.inMilliseconds / 1000).toStringAsFixed(1);

    return 'logger_builder: $_pending log event${_pending == 1 ? '' : 's'} '
        'dropped in the last ${seconds}s (${_causeText()}).';
  }

  String _causeText() => _causes.map((cause) => cause.text).join(', ');
}
