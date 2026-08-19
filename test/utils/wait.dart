import 'dart:async';

/// Waits until [done] is true, or gives up after [timeout].
///
/// Replaces `await Future.delayed(const Duration(milliseconds: 20))` followed
/// by an exact assertion. The assertion is unchanged — this only stops the
/// test from deciding, on a machine that hiccupped, that a queue which needed
/// twenty-five milliseconds had failed to do its work in twenty.
///
/// A fixed window is fine when it is a *lower* bound being tested (the retry
/// delay really spaces attempts out) and wrong when it is merely the time
/// something is expected to need. Those are the calls this replaces.
Future<void> pumpUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = Stopwatch()..start();
  while (!done() && deadline.elapsed < timeout) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
