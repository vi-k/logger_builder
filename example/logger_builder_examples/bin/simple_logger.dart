import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/simple_logger.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/simple_logger.dart && ./example/logger_builder_examples/bin/simple_logger.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  title('Default usage:');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  title('level = Level.info:');
  log.level = Levels.info;
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  title('Level.error:');
  log.level = Levels.error;
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');
  log.level = Levels.all;

  title('Access to level logger:');
  log[Levels.debug].log('Debug message');
  log[Levels.info].log('Info message');
  log[Levels.error].log('Error message');

  title('Custom builder:');
  log.builder =
      (entry) => '[${entry.levelName.toUpperCase()}] ${entry.message}';
  log[Levels.debug].log('Debug message');
  log[Levels.info].log('Info message');
  log[Levels.error].log('Error message');
  log.builder = Logger.defaultBuilder;

  title('Custom printer:');
  log[Levels.error].printer = (text) => print('$fgRed$text$reset');
  log[Levels.debug].log('Debug message');
  log[Levels.info].log('Info message');
  log[Levels.error].log('Error message');
  log.printer = print;
}
