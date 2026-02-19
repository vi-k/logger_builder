import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<void> main() async {
  final log = SimpleLogger()..level = Levels.all;

  final asyncPrinter = AsyncLogPrinter<String>((message) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print(message);
  });

  log.printer = asyncPrinter.publisher;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  print('end of main');
}
