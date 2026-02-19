import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<void> main() async {
  final log = SimpleLogger()..level = Levels.all;

  final asyncPrinter = AsyncBufferedLogPrinterWithParam<String, bool>((
    entries,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('Send messages: ${entries.length}');
    for (final (message, isError) in entries) {
      if (isError) {
        print('\x1B[31m$message\x1B[0m');
      } else {
        print(message);
      }
    }
    return [];
  });

  log.printer = asyncPrinter.publisher(false);
  log[Levels.error].printer = asyncPrinter.publisher(true);

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
