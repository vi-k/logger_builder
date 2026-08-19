import 'dart:io';
import 'dart:math' as math;

import 'console.dart';

/// How a result is highlighted.
///
/// Colour and nothing else: it does not change what is measured, how many
/// repeats are taken, or which of them are kept. The enum used to be called
/// `BenchmarkMode` with values `best` and `worst`, which read like a choice
/// of statistic and was not one.
enum Highlight {
  normal('[b]', '[/b]'),
  good('[on]', '[/on]'),
  bad('[err]', '[/err]');

  final String start;
  final String end;

  const Highlight(this.start, this.end);
}

/// Nanoseconds per call of an empty loop, measured once by [measureFloor].
///
/// Reported next to the results rather than subtracted from them: the
/// subtraction would be one more thing to trust, while a number printed
/// beside a 1.9 ns result tells the reader directly how much of it is the
/// loop.
double? _floorNs;

/// True when the program runs from `dart run` rather than a compiled
/// executable.
///
/// The two differ enough to matter and in *both* directions — AOT is faster
/// on a disabled level, the JIT on an enabled one — so a result that does
/// not say which it came from cannot be compared with anything.
bool get _isJit =>
    !Platform.resolvedExecutable.endsWith('benchmarks.exe') &&
    Platform.script.path.endsWith('.dart');

void benchmarkTitle({required String file}) {
  title('\nBenchmarks:');
  line('Usage:');
  description(
    'AOT: dart compile exe example/logger_builder_examples/bin/$file.dart && ./example/logger_builder_examples/bin/$file.exe',
  );
  description('JIT: dart run example/logger_builder_examples/bin/$file.dart');
  line('\nEnable asserts:');
  description(
    'dart compile exe --enable-asserts example/logger_builder_examples/bin/$file.dart && ./example/logger_builder_examples/bin/$file.exe',
  );
  line('\nThis run:');
  description('${_isJit ? 'JIT (dart run)' : 'AOT (compiled)'} · '
      'Dart ${Platform.version.split(' ').first} · '
      '${Platform.operatingSystem} ${Platform.localHostname}');
}

/// Measures the empty loop and remembers it as the floor of the scale.
///
/// Call once, before the sections. Every disabled-level result carries this
/// cost inside it, and at 1-2 ns per call that is not a rounding error.
void measureFloor({int count = 1000000, int repeats = 10}) {
  final samples = _sample(
    (c) {
      for (var i = 0; i < c; i++) {}
    },
    count,
    repeats,
  );
  _floorNs = _median(samples) / count * 1000;
  line('\nEmpty loop: ${_floorNs!.toStringAsFixed(2)} ns per iteration');
  description(
    'The floor of every number below. Not subtracted from them — printed '
    'here so you can subtract it yourself where it matters.',
  );
}

List<int> _sample(void Function(int count) test, int count, int repeats) {
  // Warm-up: a full pass, so the JIT has optimised the loop before the
  // stopwatch starts.
  test(count);

  final samples = <int>[];
  final sw = Stopwatch();
  for (var i = 0; i < repeats; i++) {
    sw
      ..reset()
      ..start();
    test(count);
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }

  return samples..sort();
}

double _median(List<int> sorted) {
  final n = sorted.length;

  return n.isOdd
      ? sorted[n ~/ 2].toDouble()
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// Runs [test] [repeats] times and reports the distribution.
///
/// The headline number is the **median**, not the mean of the best half the
/// harness used to print. That mean was biased low by construction and came
/// with nothing to judge it by, which is how the README ended up asserting a
/// 0.2 ns difference that does not reproduce. Everything needed to see
/// whether a gap is real is on the second line.
void runTest(
  void Function(int count) test, {
  int count = 1000000,
  int repeats = 10,
  int k = 1,
  Highlight highlight = Highlight.normal,
}) {
  final samples = _sample(test, count, repeats);
  final perCall = samples.map((us) => us / count / k * 1000).toList();
  final med = _median(samples) / count / k * 1000;
  final mean = perCall.reduce((a, b) => a + b) / perCall.length;
  final variance =
      perCall.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
          perCall.length;
  final sd = math.sqrt(variance);

  String n(double ns) => '${ns.toStringAsFixed(2)} ns';

  line('Time per call: ${highlight.start}${n(med)}${highlight.end}');
  description('median of $repeats · min ${n(perCall.first)} · '
      'max ${n(perCall.last)} · mean ${n(mean)} · sd ${n(sd)}'
      '${_floorNs == null ? '' : ' · empty loop ${n(_floorNs!)}'}');
}
