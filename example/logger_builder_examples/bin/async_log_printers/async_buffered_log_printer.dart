import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<void> main() async {
  final log = SimpleLogger()..level = Levels.all;

  final asyncPrinter = AsyncBufferedLogPrinter<String>((messages) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('Send messages: ${messages.length}');
    messages.forEach(print);
    return [];
  });

  log.printer = asyncPrinter.publisher;

  log.d('1 Debug message');
  log.i('1 Info message');
  log.e('1 Error message');
  await null;
  log.d('2 Debug message');
  log.i('2 Info message');
  log.e('2 Error message');
  log.d('3 Debug message');
  log.i('3 Info message');
  log.e('3 Error message');

  print('end of main');
}
