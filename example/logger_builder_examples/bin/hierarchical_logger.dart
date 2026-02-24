import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/hierarchical_logger.dart';

String alternativeBuilder(LogEntry entry) =>
    '${entry.levelName.toUpperCase()}: ${entry.message}';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/hierarchical_logger.dart && ./example/logger_builder_examples/bin/hierarchical_logger.exe
/// ```
Future<void> main() async {
  final log1 = Logger('unit')..level = Levels.all;
  final log2 = log1.withAddedName('feature');
  final log3 = log2.withAddedName('class');

  //
  title('Initial state:');

  description('log1');
  log1.d('Debug message');
  log1.i('Info message');
  log1.e('Error message');

  description('log2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('log3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  //
  title('level = $Levels.info:');
  log1.level = Levels.info;

  description('log1');
  log1.d('Debug message');
  log1.i('Info message');
  log1.e('Error message');

  description('log2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('log3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log1.level = Levels.all;

  //
  title('change common builder:');
  log1.builder = alternativeBuilder;

  description('log1');
  log1.d('Debug message');
  log1.i('Info message');
  log1.e('Error message');

  description('log2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('log3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log1.builder = Logger.defaultBuilder;

  //
  title('change info builder only:');
  log1[Levels.info].builder = alternativeBuilder;

  description('log1');
  log1.d('Debug message');
  log1.i('Info message');
  log1.e('Error message');

  description('log2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('log3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log1.builder = Logger.defaultBuilder;

  //
  title('change log2 builder:');
  box(
    'After installing its own builder on the'
    '\nsublogger, builder unlinks from the parent.'
    '\n${bold}This cannot be restored.$resetBoldAndFaint',
  );
  log2.builder = alternativeBuilder;

  description('log1');
  log1.d('Debug message');
  log1.i('Info message');
  log1.e('Error message');

  description('log2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('log3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log1.builder = Logger.defaultBuilder;

  //
  title('change common printer and error printer:');

  log1.printer = (text) => print('$fgGreen$text$reset');
  log1[Levels.error].printer = (text) => print('$fgRed$text$reset');

  description('log1');
  log1.d('Debug message');
  log1.i('Info message');
  log1.e('Error message');

  description('log2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('log3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log1.printer = print;

  //
  title('change log3 printer:');
  box(
    'After installing its own printer on the'
    '\nsublogger, printer unlinks from the parent.'
    '\n${bold}This cannot be restored.$resetBoldAndFaint',
  );

  log3.printer = (_) {};

  description('log1');
  log1.d('Debug message');
  log1.i('Info message');
  log1.e('Error message');

  description('log2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('log3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log1.printer = print;
}
