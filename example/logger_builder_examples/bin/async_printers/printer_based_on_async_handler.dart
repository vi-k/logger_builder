import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_printers/printer_based_on_async_handler.dart && ./example/logger_builder_examples/bin/async_printers/printer_based_on_async_handler.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  // Async printer based on `AsyncHandler`

  final asyncPrinter1 = AsyncHandler<String>((message) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('1: $message');
  });
  log.printer = asyncPrinter1.publish;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPrinter1.flush();

  // Async printer based on `AsyncHandlerBase`

  final asyncPrinter2 = MyAsyncPrinter();
  log.printer = asyncPrinter2.publish;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPrinter2.flush();

  print('end of main');
}

final class MyAsyncPrinter extends AsyncHandlerBase<String> {
  @override
  FutureOr<void> handle(String message) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('2: $message');
  }
}
