import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_log_printers/async_log_printer_with_param.dart && ./example/logger_builder_examples/bin/async_log_printers/async_log_printer_with_param.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  final asyncPrinter = AsyncLogPrinterWithParam<String, bool>((
    message,
    isError,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (isError) {
      print('$fgRed$message$reset');
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
