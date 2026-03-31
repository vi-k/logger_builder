import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/hierarchical_logger.dart';

final class DefaultLogPublisher implements CustomLogPublisher<Log> {
  const DefaultLogPublisher();

  static String format(Log log) =>
      '[${log.shortLevelName}] ${log.path} | ${log.message}';

  static void output(String out) => print(out);

  @override
  void publish(Log log) {
    output(format(log));
  }
}

Future<void> main() async {
  final log1 = Logger('unit')
    ..level = Levels.all
    ..publisher = const DefaultLogPublisher();
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
  title('change common formatter:');
  log1.publisher = CustomLogFormatter(
    format: (log) => '${log.levelName.toUpperCase()}: ${log.message}',
    output: DefaultLogPublisher.output,
  );

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

  log1.publisher = const DefaultLogPublisher();

  //
  title('change error printer:');

  log1[Levels.error].publisher = CustomLogFormatter(
    format: DefaultLogPublisher.format,
    output: (str) => DefaultLogPublisher.output('$fgRed$str$reset'),
  );

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

  log1.publisher = const DefaultLogPublisher();

  //
  title('change log2 publisher:');
  box(
    'After installing its own publisher on the sublogger, publisher'
    '\nunlinks from the parent.'
    ' ${bold}This cannot be restored.$resetBoldAndDim',
  );
  log2.publisher = CustomLogFormatter(
    format: DefaultLogPublisher.format,
    output: (str) => DefaultLogPublisher.output('$fgWhite$str$reset'),
  );

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

  // This change will not affect log2
  log1.publisher = const DefaultLogPublisher();

  //
  title('change log3 publisher:');
  box(
    'After installing its own publisher on the sublogger, publisher'
    '\nunlinks from the parent.'
    ' ${bold}This cannot be restored.$resetBoldAndDim',
  );

  log3.publisher = CustomLogFormatter(
    format: DefaultLogPublisher.format,
    output: (str) => DefaultLogPublisher.output('$fgYellow$str$reset'),
  );

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

  // This change will not affect log2 and log3
  log1.publisher = const DefaultLogPublisher();
}
