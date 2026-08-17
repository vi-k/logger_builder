import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/benchmark.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/hierarchical_logger.dart';
import 'package:logging/logging.dart' as l;
import 'package:talker_logger/talker_logger.dart' as t;

// Usage:
//
// dart compile exe example/logger_builder_examples/bin/benchmarks.dart && ./example/logger_builder_examples/bin/benchmarks.exe

String builder(Log log) => '[${log.levelName}] ${log.message}';

final class BenchmarkLogFormatter implements CustomLogPublisher<Log> {
  const BenchmarkLogFormatter();

  @override
  void publish(Log log) {
    builder(log);
  }
}

final class BenchmarkLogPrinter implements CustomLogPublisher<Log> {
  const BenchmarkLogPrinter();

  @override
  void publish(Log log) {
    print(builder(log));
  }
}

// Two loggers that differ in exactly one line: how `processLog` is produced.
// The README says the method-backed variant "should theoretically be more
// performant, as it does not create a `closure` on each call", and the section
// below is what that claim is measured against.
//
// The payload is deliberately the cheapest possible — one field, no lazy
// wrapper, a publisher that only parks the message — so that the dispatch
// itself is what the numbers are about.

Object? sink;

final class MicroLog extends CustomLog {
  final Object? message;

  MicroLog(super.levelLogger, {required this.message});
}

final class MicroPublisher implements CustomLogPublisher<MicroLog> {
  const MicroPublisher();

  @override
  void publish(MicroLog log) {
    sink = log.message;
  }
}

final class ClosureLevelLogger extends CustomLevelLogger<ClosureLogger,
    ClosureLevelLogger, LogFn, MicroLog> {
  ClosureLevelLogger({required super.level, required super.name})
      : super(
          noLog: (_, {error, stackTrace}) => true,
        );

  @override
  LogFn get processLog => (message, {error, stackTrace}) {
        publishLog(MicroLog(this, message: message));

        return true;
      };
}

final class ClosureLogger
    extends CustomLogger<ClosureLogger, ClosureLevelLogger, LogFn, MicroLog> {
  ClosureLogger();

  final ClosureLevelLogger _i =
      ClosureLevelLogger(level: Levels.info, name: 'info');

  LogFn get i => _i.log;

  @override
  void registerLevels() {
    registerLevel(_i);
  }
}

final class MethodLevelLogger extends CustomLevelLogger<MethodLogger,
    MethodLevelLogger, LogFn, MicroLog> {
  MethodLevelLogger({required super.level, required super.name})
      : super(
          noLog: (_, {error, stackTrace}) => true,
        );

  @override
  LogFn get processLog => _processLog;

  bool _processLog(Object? message, {Object? error, StackTrace? stackTrace}) {
    publishLog(MicroLog(this, message: message));

    return true;
  }
}

final class MethodLogger
    extends CustomLogger<MethodLogger, MethodLevelLogger, LogFn, MicroLog> {
  MethodLogger();

  final MethodLevelLogger _i =
      MethodLevelLogger(level: Levels.info, name: 'info');

  LogFn get i => _i.log;

  @override
  void registerLevels() {
    registerLevel(_i);
  }
}

Future<void> main() async {
  final log = Logger('root')..level = Levels.all;

  benchmarkTitle(file: 'benchmarks');

  title('Sample:');

  // CustomLogger:
  line('CustomLogger:');
  log
    ..publisher = const BenchmarkLogPrinter()
    ..i('Info message')
    ..publisher = const BenchmarkLogFormatter();

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
  runTest(mode: BenchmarkMode.worst, (count) {
    for (var i = 0; i < count; i++) {
      logLog.info('Info message #${++counter}');
    }
  });

  subtitle('talker:');
  runTest(mode: BenchmarkMode.worst, (count) {
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
  runTest(mode: assertEnabled ? BenchmarkMode.normal : BenchmarkMode.best,
      (count) {
    for (var i = 0; i < count; i++) {
      assert(log.i(evaluateMessage));
    }
  });

  subtitle('logging:');
  runTest(mode: assertEnabled ? BenchmarkMode.normal : BenchmarkMode.best,
      (count) {
    for (var i = 0; i < count; i++) {
      assert(() {
        logLog.info(evaluateMessage);
        return true;
      }());
    }
  });

  subtitle('talker:');
  runTest(mode: assertEnabled ? BenchmarkMode.normal : BenchmarkMode.best,
      (count) {
    for (var i = 0; i < count; i++) {
      assert(() {
        talkLogOn.info(evaluateMessage);
        return true;
      }());
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

  subtitle('logging:');
  runTest(mode: logging ? BenchmarkMode.normal : BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      if (logging) logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  runTest(mode: logging ? BenchmarkMode.normal : BenchmarkMode.best, (count) {
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
  // ignore: avoid_redundant_argument_values
  runTest(mode: !logging ? BenchmarkMode.normal : BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      if (!logging) logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  // ignore: avoid_redundant_argument_values
  runTest(mode: !logging ? BenchmarkMode.normal : BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      if (!logging) talkLogOn.info(evaluateMessage);
    }
  });

  // The sections above compare packages. The two below compare `CustomLogger`
  // with itself, because that is what the README's own advice is about.
  //
  // The three ways of handing over the same cheap message are not
  // interchangeable. `evaluateMessage` is a tear-off of a function that
  // already exists, so it costs no allocation per call; `() => ...` is a fresh
  // closure on every call, capturing `counter`, and that allocation happens
  // whether the level is on or off — the argument is built at the call site,
  // before the logger sees it. Everything the README recommends is written in
  // the second form.

  //
  title('Cheap payload, three ways (logging [on]enabled[/on]):');

  log.level = Levels.all;

  subtitle(r"eager: log.i('Info message #${++counter}'):");
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${++counter}');
    }
  });

  subtitle('tear-off: log.i(evaluateMessage):');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i(evaluateMessage);
    }
  });

  subtitle(r"closure literal: log.i(() => 'Info message #${++counter}'):");
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i(() => 'Info message #${++counter}');
    }
  });

  //
  title('Cheap payload, three ways (logging [off]disabled[/off]):');

  log.level = Levels.off;

  subtitle(r"eager: log.i('Info message #${++counter}'):");
  runTest(mode: BenchmarkMode.worst, (count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${++counter}');
    }
  });

  subtitle('tear-off: log.i(evaluateMessage):');
  runTest(mode: BenchmarkMode.best, (count) {
    for (var i = 0; i < count; i++) {
      log.i(evaluateMessage);
    }
  });

  subtitle(r"closure literal: log.i(() => 'Info message #${++counter}'):");
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i(() => 'Info message #${++counter}');
    }
  });

  //
  title('processLog: closure vs method (logging [on]enabled[/on]):');

  final closureLog = ClosureLogger()
    ..level = Levels.all
    ..publisher = const MicroPublisher();
  final methodLog = MethodLogger()
    ..level = Levels.all
    ..publisher = const MicroPublisher();

  subtitle('LogFn get processLog => (message, {...}) { ... }:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      closureLog.i('Info message');
    }
  });

  subtitle('LogFn get processLog => _processLog:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      methodLog.i('Info message');
    }
  });

  // Touch the sink: a store nothing ever reads is a store the compiler is
  // free to drop, and then the two variants above would be measured empty.
  description('\nLast message parked by MicroPublisher: ${sink ?? '<none>'}');
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
