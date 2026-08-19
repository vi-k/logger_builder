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

/// Where every measured value is parked so the compiler cannot drop the work
/// that produced it.
///
/// Read once at the end of `main`. A store nothing ever reads is a store the
/// compiler is free to remove, and then the section above it measures an
/// empty loop. Dart 3.13 does not currently remove the discarded `builder`
/// call — measured, 80.27 ns discarded against 81.20 ns parked — but that is
/// a fact about today's compiler, not a property of the benchmark.
Object? sink;

final class BenchmarkLogFormatter implements CustomLogPublisher<Log> {
  const BenchmarkLogFormatter();

  @override
  void publish(Log log) {
    sink = builder(log);
  }
}

/// Like [BenchmarkLogFormatter], but it reads `log.path`.
///
/// The path of this example's `Log` is a `LazyString` built from a closure
/// that walks up the parents, so nothing resolves it unless a publisher asks
/// for it — and no section did, which left the lazy path of a sublogger
/// unmeasured even in the sections that had subloggers.
String pathBuilder(Log log) =>
    '[${log.levelName}] ${log.path} | ${log.message}';

final class BenchmarkPathFormatter implements CustomLogPublisher<Log> {
  const BenchmarkPathFormatter();

  @override
  void publish(Log log) {
    sink = pathBuilder(log);
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

  measureFloor();

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
  // Wraps instead of climbing. Shared across the file and never reset, this
  // counter reached nine digits by the late sections while the early ones
  // interpolated one, and the sections are quoted against each other.
  // Measured drift: 44.25 ns counting from zero against 45.46 ns counting
  // from 250 000 000, +2.7 % — larger than several of the differences this
  // file is cited for.
  var counter = 0;
  int nextCount() => counter = counter >= 1000000 ? 1 : counter + 1;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${nextCount()}');
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.ALL;
  runTest((count) {
    for (var i = 0; i < count; i++) {
      logLog.info('Info message #${nextCount()}');
    }
  });

  subtitle('talker:');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      talkLogOn.info('Info message #${nextCount()}');
    }
  });

  //
  title('String interpolation (logging [off]disabled[/off]):');

  subtitle('CustomLogger:');
  log.level = Levels.off;
  runTest(highlight: Highlight.bad, (count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${nextCount()}');
    }
  });

  subtitle('logging:');
  l.Logger.root.level = l.Level.OFF;
  runTest(highlight: Highlight.bad, (count) {
    for (var i = 0; i < count; i++) {
      logLog.info('Info message #${nextCount()}');
    }
  });

  subtitle('talker:');
  runTest(highlight: Highlight.bad, (count) {
    for (var i = 0; i < count; i++) {
      talkLogOff.info('Info message #${nextCount()}');
    }
  });

  //
  title('Lazy string (logging [on]enabled[/on]):');

  subtitle('CustomLogger:');
  log.level = Levels.all;
  String evaluateMessage() => 'Info message #${nextCount()}';
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
  runTest(highlight: Highlight.good, (count) {
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
  runTest(highlight: assertEnabled ? Highlight.normal : Highlight.good,
      (count) {
    for (var i = 0; i < count; i++) {
      assert(log.i(evaluateMessage));
    }
  });

  subtitle('logging:');
  runTest(highlight: assertEnabled ? Highlight.normal : Highlight.good,
      (count) {
    for (var i = 0; i < count; i++) {
      assert(() {
        logLog.info(evaluateMessage);
        return true;
      }());
    }
  });

  subtitle('talker:');
  runTest(highlight: assertEnabled ? Highlight.normal : Highlight.good,
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
  runTest(highlight: logging ? Highlight.normal : Highlight.good, (count) {
    for (var i = 0; i < count; i++) {
      logging && log.i(evaluateMessage);
    }
  });

  subtitle('logging:');
  runTest(highlight: logging ? Highlight.normal : Highlight.good, (count) {
    for (var i = 0; i < count; i++) {
      if (logging) logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  runTest(highlight: logging ? Highlight.normal : Highlight.good, (count) {
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
  runTest(highlight: !logging ? Highlight.normal : Highlight.good, (count) {
    for (var i = 0; i < count; i++) {
      !logging && log.i(evaluateMessage);
    }
  });

  subtitle('logging:');
  // ignore: avoid_redundant_argument_values
  runTest(highlight: !logging ? Highlight.normal : Highlight.good, (count) {
    for (var i = 0; i < count; i++) {
      if (!logging) logLog.info(evaluateMessage);
    }
  });

  subtitle('talker:');
  // ignore: avoid_redundant_argument_values
  runTest(highlight: !logging ? Highlight.normal : Highlight.good, (count) {
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

  subtitle(r"eager: log.i('Info message #${nextCount()}'):");
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${nextCount()}');
    }
  });

  subtitle('tear-off: log.i(evaluateMessage):');
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i(evaluateMessage);
    }
  });

  subtitle(r"closure literal: log.i(() => 'Info message #${nextCount()}'):");
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i(() => 'Info message #${nextCount()}');
    }
  });

  //
  title('Cheap payload, three ways (logging [off]disabled[/off]):');

  log.level = Levels.off;

  subtitle(r"eager: log.i('Info message #${nextCount()}'):");
  runTest(highlight: Highlight.bad, (count) {
    for (var i = 0; i < count; i++) {
      log.i('Info message #${nextCount()}');
    }
  });

  subtitle('tear-off: log.i(evaluateMessage):');
  runTest(highlight: Highlight.good, (count) {
    for (var i = 0; i < count; i++) {
      log.i(evaluateMessage);
    }
  });

  subtitle(r"closure literal: log.i(() => 'Info message #${nextCount()}'):");
  runTest((count) {
    for (var i = 0; i < count; i++) {
      log.i(() => 'Info message #${nextCount()}');
    }
  });

  //
  // Depth was measured nowhere at all, and it is the one thing in the package
  // that can grow with it. Until `534f342` `onError` was resolved by walking
  // the parent chain on every published log: 9.4 ns at depth 0 against
  // 57.7 ns at depth 20 in AOT, while the disabled path stayed flat. A flat
  // enabled curve here is the guard against that coming back.
  Logger atDepth(int depth, CustomLogPublisher<Log> publisher) {
    var node = Logger('root')
      ..level = Levels.all
      ..publisher = publisher;
    for (var i = 0; i < depth; i++) {
      node = node.child('n$i');
    }

    return node;
  }

  const depths = [0, 1, 5, 20];

  title('Sublogger depth (logging [on]enabled[/on]):');

  for (final depth in depths) {
    final node = atDepth(depth, const BenchmarkLogFormatter());
    subtitle('depth $depth:');
    runTest((count) {
      for (var i = 0; i < count; i++) {
        node.i('Info message');
      }
    });
  }

  //
  title('Sublogger depth (logging [off]disabled[/off]):');

  for (final depth in depths) {
    final node = atDepth(depth, const BenchmarkLogFormatter())
      ..level = Levels.off;
    subtitle('depth $depth:');
    runTest(highlight: Highlight.good, (count) {
      for (var i = 0; i < count; i++) {
        node.i('Info message');
      }
    });
  }

  //
  title('Sublogger depth, publisher reads the path '
      '(logging [on]enabled[/on]):');

  for (final depth in depths) {
    final node = atDepth(depth, const BenchmarkPathFormatter());
    subtitle('depth $depth:');
    runTest((count) {
      for (var i = 0; i < count; i++) {
        node.i('Info message');
      }
    });
  }

  //
  // The publishing layer, none of which was measured before: `MultiPublisher`,
  // `TransformPublisher` and `CustomLogger.transformer` are public API, all
  // three sit on the publish path of every log, and the repository had no
  // number for any of them.
  title('The publishing layer (logging [on]enabled[/on]):');

  subtitle('publisher alone:');
  final plainLog = Logger('plain')
    ..level = Levels.all
    ..publisher = const BenchmarkLogFormatter();
  runTest((count) {
    for (var i = 0; i < count; i++) {
      plainLog.i('Info message');
    }
  });

  subtitle('+ CustomLogger.transformer (identity):');
  final transformedLog = Logger('transformed')
    ..level = Levels.all
    ..publisher = const BenchmarkLogFormatter()
    ..transformer = ((log) => log);
  runTest((count) {
    for (var i = 0; i < count; i++) {
      transformedLog.i('Info message');
    }
  });

  subtitle('+ TransformPublisher (identity):');
  final wrappedLog = Logger('wrapped')
    ..level = Levels.all
    ..publisher = TransformPublisher<Log>(
      const BenchmarkLogFormatter(),
      transformer: (log) => log,
    );
  runTest((count) {
    for (var i = 0; i < count; i++) {
      wrappedLog.i('Info message');
    }
  });

  for (final fanOut in [1, 2, 4]) {
    subtitle('MultiPublisher of $fanOut:');
    final multiLog = Logger('multi$fanOut')
      ..level = Levels.all
      ..publisher = MultiPublisher<Log>([
        for (var i = 0; i < fanOut; i++) const BenchmarkLogFormatter(),
      ]);
    runTest((count) {
      for (var i = 0; i < count; i++) {
        multiLog.i('Info message');
      }
    });
  }

  //
  // The asynchronous publishers, which had no number anywhere. The dartdoc
  // of `flush` even claimed that flushing after every log is "measurably
  // more expensive" — a claim with no measurement behind it until now.
  //
  // Each figure is "hand n logs over and wait until the queue is empty", so
  // it includes the drain, which is what anyone asking about an asynchronous
  // publisher wants to know.
  title('Asynchronous publishers, per log including the drain:');

  subtitle('AsyncPublisher, one log at a time:');
  await runAsyncTest((count) async {
    final publisher = AsyncPublisher<Log>((log) => sink = log.message);
    final log = Logger('async')
      ..level = Levels.all
      ..publisher = publisher;
    for (var i = 0; i < count; i++) {
      log.i('Info message');
    }
    await publisher.flush();
    await publisher.close();
  });

  subtitle('AsyncPublisher with sync: true:');
  await runAsyncTest((count) async {
    final publisher =
        AsyncPublisher<Log>((log) => sink = log.message, sync: true);
    final log = Logger('async')
      ..level = Levels.all
      ..publisher = publisher;
    for (var i = 0; i < count; i++) {
      log.i('Info message');
    }
    await publisher.flush();
    await publisher.close();
  });

  subtitle('AsyncPublisherWithBuffer, batched:');
  await runAsyncTest((count) async {
    final publisher = AsyncPublisherWithBuffer<Log>(
      (logs, retry) => sink = logs.length,
    );
    final log = Logger('buffered')
      ..level = Levels.all
      ..publisher = publisher;
    for (var i = 0; i < count; i++) {
      log.i('Info message');
    }
    await publisher.flush();
    await publisher.close();
  });

  subtitle('AsyncPublisherWithBuffer, flushed after every log:');
  await runAsyncTest(
    count: 2000,
    highlight: Highlight.bad,
    (count) async {
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retry) => sink = logs.length,
      );
      final log = Logger('buffered')
        ..level = Levels.all
        ..publisher = publisher;
      for (var i = 0; i < count; i++) {
        log.i('Info message');
        await publisher.flush();
      }
      await publisher.close();
    },
  );

  subtitle('AsyncPublisher, flushed after every log:');
  await runAsyncTest(
    count: 2000,
    highlight: Highlight.bad,
    (count) async {
      final publisher = AsyncPublisher<Log>((log) => sink = log.message);
      final log = Logger('async')
        ..level = Levels.all
        ..publisher = publisher;
      for (var i = 0; i < count; i++) {
        log.i('Info message');
        await publisher.flush();
      }
      await publisher.close();
    },
  );

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
  // free to drop, and then everything above would be measured empty.
  description('\nLast value parked: ${sink ?? '<none>'}');
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
