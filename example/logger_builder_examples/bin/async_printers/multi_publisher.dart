import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger_without_printer.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_printers/async_builder.dart && ./example/logger_builder_examples/bin/async_printers/async_builder.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  final multiPublisher = MultiPublisher([
    AsyncHandler<LogEntry>((entry) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      print('handler#1: ${entry.message}');
    }).publish,
    AsyncBuffer<LogEntry>((entries) async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      print('handler#2: Send ${entries.length} messages:');
      for (final (index, entry) in entries.indexed) {
        print('handler#2: (${index + 1}) ${entry.message}');
      }
      return [];
    }).publish,
  ]);

  log.builder = multiPublisher.publish;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  print('end of main');
}
