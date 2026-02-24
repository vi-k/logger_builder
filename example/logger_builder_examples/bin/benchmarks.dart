import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/benchmark.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/hierarchical_logger.dart';
import 'package:logging/logging.dart' as l;
import 'package:talker_logger/talker_logger.dart' as t;

String builder(LogEntry entry) => '[${entry.levelName}] ${entry.message}';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/benchmarks.dart && ./example/logger_builder_examples/bin/benchmarks.exe
/// ```
Future<void> main() async {
  final log = Logger('root')..level = Levels.all;

  benchmarkTitle('benchmarks');

  title('Sample:');

  // CustomLogger:
  line('CustomLogger:');
  log
    ..builder = builder
    ..printer = print
    ..i('Info message')
    ..printer = (_) {};

  // logging
  //
  // Put the logger on equal footing with `CustomLogger`:
  // - calculate the final string
  // - set an empty printer call
  void Function(String) printer = print;
  l.Logger.root.onRecord.listen((record) {
    final text = '[${record.level.name}] ${record.message}';
    printer(text);
  });
  final logLog = l.Logger('logging');
  line('\nlogging:');
  logLog.info('Info message');
  printer = (_) {};

  // talker
  //
  // Put the logger on equal footing with `CustomLogger`:
  // - calculate the final string
  // - set an empty output call
  final formatter = TalkerSimpleLoggerFormatter();
  final talkSampleLog = t.TalkerLogger(formatter: formatter);
  line('\ntalker:');
  talkSampleLog.info('Info message');

  final talkLogOn = t.TalkerLogger(formatter: formatter, output: (_) {});

  final talkLogOff = t.TalkerLogger(
    formatter: formatter,
    settings: t.TalkerLoggerSettings(level: t.LogLevel.critical),
    output: (_) {},
  );

  //
  title('Constant string (logging [on]enabled[/on]):');

  subtitle('CustomLogger:');
  log.level = Levels.all;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message');
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.ALL;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      logLog.info('Info message');
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      talkLogOn.info('Info message');
    }
  });

  //
  title('Constant string (logging [off]disabled[/off]):');

  subtitle('CustomLogger:');
  log.level = Levels.off;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message');
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.OFF;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      logLog.info('Info message');
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      talkLogOff.info('Info message');
    }
  });

  //
  title('String interpolation (logging [on]enabled[/on]):');

  subtitle('CustomLogger:');
  log.level = Levels.all;
  var counter = 0;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${++counter}');
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.ALL;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      logLog.info('Info message #${++counter}');
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      talkLogOn.info('Info message #${++counter}');
    }
  });

  //
  title('String interpolation (logging [off]disabled[/off]):');

  subtitle('CustomLogger:');
  log.level = Levels.off;
  runTest(mode: BenchmarkMode.worst, (count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${++counter}');
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.OFF;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      logLog.info('Info message #${++counter}');
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      talkLogOff.info('Info message #${++counter}');
    }
  });

  //
  title('Lazy string (logging [on]enabled[/on]):');

  subtitle('CustomLogger:');
  log.level = Levels.all;
  String evaluateMessage() => 'Info message #${++counter}';
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i(evaluateMessage);
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.ALL;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      talkLogOn.info(evaluateMessage);
    }
  });

  //
  title('Lazy string (logging [off]disabled[/off]):');

  subtitle('CustomLogger:');
  log.level = Levels.off;
  runTest(mode: BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      log.i(evaluateMessage);
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.OFF;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      talkLogOff.info(evaluateMessage);
    }
  });

  log.level = Levels.all;
  l.Logger.root.level = l.Level.ALL;
  var assertEnabled = false;
  assert((() => assertEnabled = true)());

  //
  title(
    'Lazy string wrapped in asserts (asserts ${assertEnabled //
        ? '[on]enabled[/on]' : '[off]disabled[/off]'}):',
  );

  subtitle('CustomLogger:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      assert(log.i(evaluateMessage));
    }
  });

  const logging = bool.fromEnvironment('logging');

  //
  title(
    'Lazy string wrapped in constant (logging ${logging //
        ? '[on]enabled[/on]' : '[off]disabled[/off]'}):',
  );

  subtitle('CustomLogger:');
  runTest(mode: logging ? BenchmarkMode.normal : BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      logging && log.i(evaluateMessage);
    }
  });

  subtitle('CustomLogger:');
  runTest(mode: logging ? BenchmarkMode.normal : BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      if (logging) log.i(evaluateMessage);
    }
  });

  subtitle('logging:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      if (logging) logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      if (logging) talkLogOn.info(evaluateMessage);
    }
  });

  //
  title(
    'Lazy string wrapped in constant'
    ' (logging ${!logging ? '[on]enabled[/on]' : '[off]disabled[/off]'}):',
  );

  subtitle('CustomLogger:');
  // ignore: avoid_redundant_argument_values
  runTest(mode: !logging ? BenchmarkMode.normal : BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      !logging && log.i(evaluateMessage);
    }
  });

  subtitle('logging:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      if (!logging) logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      if (!logging) talkLogOn.info(evaluateMessage);
    }
  });
}

class TalkerSimpleLoggerFormatter extends t.LoggerFormatter {
  TalkerSimpleLoggerFormatter() : super();

  @override
  String fmt(t.LogDetails details, t.TalkerLoggerSettings settings) {
    final obj = switch (details.message) {
      final Object? Function() func => func(),
      final Object? msg => msg,
    };
    final message = switch (obj) {
      final String msg => msg,
      final Object? msg => msg.toString(),
    };

    // The time will not be displayed, but we take it to put the loggers in the
    // same conditions.
    // ignore: unused_local_variable
    final time = DateTime.now();

    final text = '[${details.level.name}] $message';
    return text;
  }
}
