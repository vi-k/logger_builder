import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger_without_printer.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_printers/async_builder.dart && ./example/logger_builder_examples/bin/async_printers/async_builder.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  final asyncBuilder = AsyncHandler<LogEntry>((entry) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print(entry.message);
  });

  log.builder = asyncBuilder.publish;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  print('end of main');
}
