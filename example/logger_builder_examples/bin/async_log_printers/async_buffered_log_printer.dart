import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_log_printers/async_buffered_log_printer.dart && ./example/logger_builder_examples/bin/async_log_printers/async_buffered_log_printer.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

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
