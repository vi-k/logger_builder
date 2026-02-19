import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/hierarchical_logger.dart';

String alternativeBuilder(HierarchicalLogEntry entry) =>
    '${entry.levelName.toUpperCase()}: ${entry.message}';

Future<void> main() async {
  final log = HierarchicalLogger('package')..level = Levels.all;
  final log2 = log.withAddedName('feature');
  final log3 = log2.withAddedName('class');

  //
  title('Initial state:');

  description('1');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  description('2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  //
  title('level = $Levels.info:');
  log.level = Levels.info;

  description('1');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  description('2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log.level = Levels.all;

  //
  title('change common builder:');
  log.builder = alternativeBuilder;

  description('1');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  description('2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log.builder = HierarchicalLogger.defaultBuilder;

  //
  title('change common info builder:');

  log[Levels.info].builder = alternativeBuilder;

  description('1');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  description('2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log.builder = HierarchicalLogger.defaultBuilder;

  //
  title('change log2 builder:');
  log2.builder = alternativeBuilder;

  description('1');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  description('2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log.builder = HierarchicalLogger.defaultBuilder;

  //
  title('change common printer:');
  description(
    'After installing its own builder on the sublogger,'
    ' builder unlinks from the parent. This cannot be restored.\n',
  );

  log.printer = (text) => print('\x1B[30m$text\x1B[0m');
  log[Levels.error].printer = (text) => print('\x1B[31m$text\x1B[0m');

  description('1');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  description('2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log.printer = print;

  //
  title('change log3 printer:');
  description(
    'After installing its own printer on the sublogger, it'
    ' printer unlinks from the parent. This cannot be restored.\n',
  );

  log3.printer = (_) {};

  description('1');
  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  description('2');
  log2.d('Debug message');
  log2.i('Info message');
  log2.e('Error message');

  description('3');
  log3.d('Debug message');
  log3.i('Info message');
  log3.e('Error message');

  log.printer = print;
}
