import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/simple_logger.dart';

final class DefaultLogPublisher implements CustomLogPublisher<Log> {
  const DefaultLogPublisher();

  static String format(Log log) => '[${log.shortLevelName}] ${log.message}';

  static void output(String out) => print(out);

  @override
  void publish(Log log) {
    output(format(log));
  }
}

Future<void> main() async {
  final log = Logger()
    ..level = Levels.all
    ..publisher = const DefaultLogPublisher();

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

  title('Custom formatter:');
  log.publisher = CustomLogFormatter(
    format: (log) => '[${log.levelName.toUpperCase()}] ${log.message}',
    output: DefaultLogPublisher.output,
  );
  log[Levels.debug].log('Debug message');
  log[Levels.info].log('Info message');
  log[Levels.error].log('Error message');
  log.publisher = const DefaultLogPublisher();

  title('Custom level printer:');
  log[Levels.error].publisher = CustomLogFormatter(
    format: DefaultLogPublisher.format,
    output: (str) => DefaultLogPublisher.output('$fgRed$str$reset'),
  );
  log[Levels.debug].log('Debug message');
  log[Levels.info].log('Info message');
  log[Levels.error].log('Error message');
  log.publisher = const DefaultLogPublisher();
}
