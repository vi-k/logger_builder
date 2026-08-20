import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

/// One side of a comparison: its median cost, in nanoseconds per call.
typedef _Shape = ({double ratio, double baseNs, double otherNs});

/// Median of [repeats] ratios, each taken from a pair of passes measured
/// back to back.
///
/// The pairing is the whole point. Measuring one side nine times and then
/// the other nine times compares two different moments in the machine's
/// life: load that arrives between the halves moves the ratio bodily, and
/// a median does not help, because it smooths nine equally skewed passes.
/// Interleaved, both sides meet the same machine within a millisecond of
/// each other — which is what this file has always claimed and did not do.
///
/// The median is still over ratios rather than over times: one descheduled
/// pair should not decide the result.
_Shape _shape(
  void Function() base,
  void Function() other, {
  int count = 200000,
  int repeats = 9,
}) {
  for (var i = 0; i < count; i++) {
    base();
    other();
  }

  final sw = Stopwatch();
  final pairs = <(int, int)>[];
  for (var r = 0; r < repeats; r++) {
    final baseUs = _passMicros(sw, base, count);
    final otherUs = _passMicros(sw, other, count);
    pairs.add((baseUs, otherUs));
  }
  pairs.sort((a, b) => (a.$2 / a.$1).compareTo(b.$2 / b.$1));
  final (baseUs, otherUs) = pairs[repeats ~/ 2];

  return (
    ratio: otherUs / baseUs,
    baseNs: baseUs / count * 1000,
    otherNs: otherUs / count * 1000,
  );
}

int _passMicros(Stopwatch sw, void Function() body, int count) {
  sw
    ..reset()
    ..start();
  for (var i = 0; i < count; i++) {
    body();
  }
  sw.stop();

  // A pass fast enough to measure as zero would make the ratio meaningless;
  // at 200 000 iterations even the cheapest side here takes about a
  // millisecond, so this only ever guards against a future shrink of count.
  return sw.elapsedMicroseconds == 0 ? 1 : sw.elapsedMicroseconds;
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
  // L11 (project review 2026-08-20[1]): "slows both sides equally" was an
  // assertion about a structure that did not hold it up. The two sides were
  // measured one after the other, nine passes each, so load arriving between
  // the halves hit one side only. They are interleaved now — see [_shape].
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

      final shape = _shape(() => root.i('message'), () => deep.i('message'));

      expect(
        shape.ratio,
        lessThan(1.5),
        reason: 'root ${shape.baseNs.toStringAsFixed(2)} ns, '
            'depth 20 ${shape.otherNs.toStringAsFixed(2)} ns',
      );
    });

    test('a disabled log costs the same at depth 20 as at the root', () {
      final root = _atDepth(0, _parking)..level = Levels.off;
      final deep = _atDepth(20, _parking)..level = Levels.off;

      final shape = _shape(() => root.i('message'), () => deep.i('message'));

      expect(
        shape.ratio,
        lessThan(1.5),
        reason: 'root ${shape.baseNs.toStringAsFixed(2)} ns, '
            'depth 20 ${shape.otherNs.toStringAsFixed(2)} ns',
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
