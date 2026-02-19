import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<void> main() async {
  final log = SimpleLogger()..level = Levels.all;

  final asyncPrinter = AsyncLogPrinterWithParam<String, bool>((
    message,
    isError,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (isError) {
      print('\x1B[31m$message\x1B[0m');
    } else {
      print(message);
    }
  });

  log.printer = asyncPrinter.publisher(false);
  log[Levels.error].printer = asyncPrinter.publisher(true);

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  print('end of main');
}
