import 'dart:developer' as development;

import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/complex_logger.dart';
import 'package:logger_builder_examples/console.dart';

final class DefaultLogPublisher implements CustomLogPublisher<Log> {
  const DefaultLogPublisher();

  static String format(Log log) => '(${log.sequenceNumber})'
      ' ${log.time.toIso8601String()} [${log.name}] '
      '${log.source == null ? '' : '${log.source} | '}'
      '${log.message}'
      '${log.error == null ? '' : ': ${log.error}'}'
      '${log.stackTrace == null || log.stackTrace == StackTrace.empty //
          ? '' : '\n${log.stackTrace}'}';

  static void output(String out) => print(out);

  @override
  void publish(Log log) => output(format(log));
}

final class MyClass {}

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/complex_logger.dart && ./example/logger_builder_examples/bin/complex_logger.exe
/// ```
Future<void> main() async {
  final log = Logger('logger_name')
    ..level = Levels.all
    ..publisher = const DefaultLogPublisher();

  title('Default usage:');
  log.finest(MyClass, 'Finest message');
  log.finer(MyClass, 'Finer message');
  log.fine(MyClass, 'Fine message');
  log.config(MyClass, 'Config message');
  log.info(MyClass, 'Info message');
  log.warning(MyClass, 'Warning message');
  log.severe(MyClass, 'Severe message');
  log.shout(MyClass, 'Shout message');

  title('level = Level.info:');
  log.level = Levels.info;
  log.finest(MyClass, 'Finest message');
  log.finer(MyClass, 'Finer message');
  log.fine(MyClass, 'Fine message');
  log.config(MyClass, 'Config message');
  log.info(MyClass, 'Info message');
  log.warning(MyClass, 'Warning message');
  log.severe(MyClass, 'Severe message');
  log.shout(MyClass, 'Shout message');

  title('Level.error:');
  log.level = Levels.error;
  log.finest(MyClass, 'Finest message');
  log.finer(MyClass, 'Finer message');
  log.fine(MyClass, 'Fine message');
  log.config(MyClass, 'Config message');
  log.info(MyClass, 'Info message');
  log.warning(MyClass, 'Warning message');
  log.severe(MyClass, 'Severe message');
  log.shout(MyClass, 'Shout message');
  log.level = Levels.all;

  title('Access to level logger:');
  log[Levels.finest].log(MyClass, 'Finest message');
  log[Levels.finer].log(MyClass, 'Finer message');
  log[Levels.fine].log(MyClass, 'Fine message');
  log[Levels.config].log(MyClass, 'Config message');
  log[Levels.info].log(MyClass, 'Info message');
  log[Levels.warning].log(MyClass, 'Warning message');
  log[Levels.severe].log(MyClass, 'Severe message');
  log[Levels.shout].log(MyClass, 'Shout message');

  title('Custom formatter:');
  log.publisher = CustomLogFormatter(
    format: (entry) => '[${entry.levelName.toUpperCase()}] ${entry.message}',
    output: DefaultLogPublisher.output,
  );
  log[Levels.finest].log(MyClass, 'Finest message');
  log[Levels.finer].log(MyClass, 'Finer message');
  log[Levels.fine].log(MyClass, 'Fine message');
  log[Levels.config].log(MyClass, 'Config message');
  log[Levels.info].log(MyClass, 'Info message');
  log[Levels.warning].log(MyClass, 'Warning message');
  log[Levels.severe].log(MyClass, 'Severe message');
  log[Levels.shout].log(MyClass, 'Shout message');
  log.publisher = const DefaultLogPublisher();

  title('Custom level printer:');
  log[Levels.severe].publisher =
      log[Levels.shout].publisher = CustomLogFormatter(
    format: DefaultLogPublisher.format,
    output: (str) => DefaultLogPublisher.output('$fgRed$str$reset'),
  );
  log[Levels.finest].log(MyClass, 'Finest message');
  log[Levels.finer].log(MyClass, 'Finer message');
  log[Levels.fine].log(MyClass, 'Fine message');
  log[Levels.config].log(MyClass, 'Config message');
  log[Levels.info].log(MyClass, 'Info message');
  log[Levels.warning].log(MyClass, 'Warning message');
  log[Levels.severe].log(MyClass, 'Severe message');
  log[Levels.shout].log(MyClass, 'Shout message');
  log.publisher = const DefaultLogPublisher();

  title('Using development.log:');
  log.publisher = CustomLogPublisher(
    (log) {
      development.log(
        '${log.source == null ? '' : '${log.source} | '}'
        '${log.message}',
        time: log.time,
        sequenceNumber: log.sequenceNumber,
        level: log.level,
        name: log.name,
        error: log.error,
        stackTrace: log.stackTrace,
        zone: log.zone,
      );
    },
  );
  log[Levels.finest].log(MyClass, 'Finest message');
  log[Levels.finer].log(MyClass, 'Finer message');
  log[Levels.fine].log(MyClass, 'Fine message');
  log[Levels.config].log(MyClass, 'Config message');
  log[Levels.info].log(MyClass, 'Info message');
  log[Levels.warning].log(MyClass, 'Warning message');
  log[Levels.severe].log(MyClass, 'Severe message');
  log[Levels.shout].log(MyClass, 'Shout message');
  log.publisher = const DefaultLogPublisher();
}
