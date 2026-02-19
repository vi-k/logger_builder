import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<void> main() async {
  final log = SimpleLogger()..level = Levels.all;

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
  log.builder = SimpleLogger.defaultBuilder;

  title('Custom printer:');
  log[Levels.error].printer = (text) => print('\x1B[31m$text\x1B[0m');
  log[Levels.debug].log('Debug message');
  log[Levels.info].log('Info message');
  log[Levels.error].log('Error message');
  log.printer = print;
}
