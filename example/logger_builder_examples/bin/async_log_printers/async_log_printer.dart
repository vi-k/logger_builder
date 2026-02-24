import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_log_printers/async_log_printer.dart && ./example/logger_builder_examples/bin/async_log_printers/async_log_printer.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

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
