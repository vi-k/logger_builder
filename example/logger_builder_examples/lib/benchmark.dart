import 'console.dart';

enum BenchmarkMode {
  normal('[b]', '[/b]'),
  best('[on]', '[/on]'),
  worst('[err]', '[/err]');

  final String start;
  final String end;

  const BenchmarkMode(this.start, this.end);
}

void benchmarkTitle(String file) {
  title('\nSimple benchmark:');
  line('Usage:');
  description(
    'dart compile exe example/pkglog_example/bin/$file.dart && ./example/pkglog_example/bin/$file.exe',
  );
  line('\nEnable asserts:');
  description(
    'dart compile exe --enable-asserts example/pkglog_example/bin/$file.dart && ./example/pkglog_example/bin/$file.exe',
  );
}

void runTest(
  void Function(int count) test, {
  int count = 1000000,
  int repeats = 10,
  int k = 1,
  BenchmarkMode mode = BenchmarkMode.normal,
}) {
  test(count);

  final sw = Stopwatch();
  final durations = <Duration>[];
  for (var i = 0; i < repeats; i++) {
    sw
      ..reset()
      ..start();
    test(count);
    sw.stop();
    durations.add(sw.elapsed);
  }
  // Take half of the best results.
  final bestResults = (durations..sort()).take(repeats ~/ 2).toList();
  final avg = bestResults.reduce((a, b) => a + b) ~/ bestResults.length;
  line('Time per call: ${mode.start}${_n(avg, count, k)}${mode.end}');
  description('Average among the top ${bestResults.length}/$repeats results');
  // description('${durations.map((d) => _n(d, count, k)).toList()}');
}

String _n(Duration duration, int count, int k) =>
    '${(duration.inMicroseconds / count / k * 1000).toStringAsFixed(2)} ns';
