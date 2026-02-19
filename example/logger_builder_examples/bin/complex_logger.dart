import 'dart:developer' as development;

import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/complex_logger.dart';
import 'package:logger_builder_examples/console.dart';

final class MyClass {}

Future<void> main() async {
  final log = ComplexLogger('logger_name')..level = Levels.all;

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

  title('Custom builder:');
  log.builder =
      (entry) => '[${entry.levelName.toUpperCase()}] ${entry.message}';
  log[Levels.finest].log(MyClass, 'Finest message');
  log[Levels.finer].log(MyClass, 'Finer message');
  log[Levels.fine].log(MyClass, 'Fine message');
  log[Levels.config].log(MyClass, 'Config message');
  log[Levels.info].log(MyClass, 'Info message');
  log[Levels.warning].log(MyClass, 'Warning message');
  log[Levels.severe].log(MyClass, 'Severe message');
  log[Levels.shout].log(MyClass, 'Shout message');
  log.builder = ComplexLogger.defaultBuilder;

  title('Custom printer:');
  log[Levels.severe].printer =
      log[Levels.shout].printer = (text) => print('\x1B[31m$text\x1B[0m');
  log[Levels.finest].log(MyClass, 'Finest message');
  log[Levels.finer].log(MyClass, 'Finer message');
  log[Levels.fine].log(MyClass, 'Fine message');
  log[Levels.config].log(MyClass, 'Config message');
  log[Levels.info].log(MyClass, 'Info message');
  log[Levels.warning].log(MyClass, 'Warning message');
  log[Levels.severe].log(MyClass, 'Severe message');
  log[Levels.shout].log(MyClass, 'Shout message');
  log.printer = print;

  title('Print via builder (development.log):');
  log
    ..printer = (_) {}
    ..builder = (entry) {
      development.log(
        '${entry.source == null ? '' : '${entry.source} | '}'
        '${entry.message}',
        time: entry.time,
        sequenceNumber: entry.sequenceNumber,
        level: entry.level,
        name: entry.name,
        error: entry.error,
        stackTrace: entry.stackTrace,
        zone: entry.zone,
      );
      return '';
    };
  log[Levels.finest].log(MyClass, 'Finest message');
  log[Levels.finer].log(MyClass, 'Finer message');
  log[Levels.fine].log(MyClass, 'Fine message');
  log[Levels.config].log(MyClass, 'Config message');
  log[Levels.info].log(MyClass, 'Info message');
  log[Levels.warning].log(MyClass, 'Warning message');
  log[Levels.severe].log(MyClass, 'Severe message');
  log[Levels.shout].log(MyClass, 'Shout message');
  log.printer = print;
}
