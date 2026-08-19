import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

/// Nanoseconds per call, median of [repeats] passes of [count] iterations.
///
/// A median rather than a mean: one descheduled pass on a shared CI runner
/// should not decide the result.
double _nsPerCall(
  void Function() body, {
  int count = 200000,
  int repeats = 9,
}) {
  for (var i = 0; i < count; i++) {
    body();
  }

  final samples = <int>[];
  final sw = Stopwatch();
  for (var r = 0; r < repeats; r++) {
    sw
      ..reset()
      ..start();
    for (var i = 0; i < count; i++) {
      body();
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();

  return samples[repeats ~/ 2] / count * 1000;
}

Logger _atDepth(int depth, CustomLogPublisher<Log> publisher) {
  var node = Logger('root')
    ..level = Levels.all
    ..publisher = publisher;
  for (var i = 0; i < depth; i++) {
    node = node.child('n$i');
  }

  return node;
}

Object? _sink;

final _parking = CustomLogPublisher<Log>((log) => _sink = log.message);

void main() {
  // Ratios, not absolutes, and loose by a factor of three: a shared runner
  // slows both sides of a ratio equally, so the shape survives a machine the
  // numbers would not. The point is not to measure anything —
  // `benchmarks.dart` does that — but to fail loudly if a shape the package
  // sells collapses.
  //
  // Only depth is asserted, and that is a deliberate narrowing. The first
  // version of this file also checked that a disabled level is ten times
  // cheaper than an enabled one, and it flaked: the ratio is a property of
  // the *payload*, not of the package. With this fixture's `Log` it is about
  // 9, with a one-field `Log` about 2, and with the string-building publisher
  // in `benchmarks.dart` about 49. Nothing stable to guard there.
  //
  // Depth is different: it is the package's own shape and it is flat to
  // within about 8 % across repeated runs. The threshold of 1.5 is measured,
  // not guessed — reinstating H1 as a store to a top-level field puts the
  // ratio at 1.73-1.76 over eight runs, while the fixed code sits at
  // 0.93-1.08.
  //
  // H1 itself has a deterministic guard elsewhere: `CountingLogger` in
  // `transformer_test.dart` asserts that a successful log does not consult
  // `onError` at all. This file is the broader net — anything that makes an
  // enabled log cost more the deeper the sublogger sits, whatever the
  // cause.
  group('performance shapes', () {
    // Regression: H1. Before `534f342` an enabled log resolved `onError` by
    // walking the parent chain every time, so this ratio was about 6 at depth
    // 20 and 30 at depth 50. It is 1.0 now.
    test('an enabled log costs the same at depth 20 as at the root', () {
      final root = _atDepth(0, _parking);
      final deep = _atDepth(20, _parking);

      final atRoot = _nsPerCall(() => root.i('message'));
      final atDepth = _nsPerCall(() => deep.i('message'));

      expect(
        atDepth / atRoot,
        lessThan(1.5),
        reason: 'root ${atRoot.toStringAsFixed(2)} ns, '
            'depth 20 ${atDepth.toStringAsFixed(2)} ns',
      );
    });

    test('a disabled log costs the same at depth 20 as at the root', () {
      final root = _atDepth(0, _parking)..level = Levels.off;
      final deep = _atDepth(20, _parking)..level = Levels.off;

      final atRoot = _nsPerCall(() => root.i('message'));
      final atDepth = _nsPerCall(() => deep.i('message'));

      expect(
        atDepth / atRoot,
        lessThan(1.5),
        reason: 'root ${atRoot.toStringAsFixed(2)} ns, '
            'depth 20 ${atDepth.toStringAsFixed(2)} ns',
      );
    });

    tearDownAll(() {
      // Touch the sink so the publisher's store cannot be optimised away,
      // which would leave the ratios measuring an empty loop against another
      // empty loop.
      expect(_sink, isNotNull);
    });
  });
}
