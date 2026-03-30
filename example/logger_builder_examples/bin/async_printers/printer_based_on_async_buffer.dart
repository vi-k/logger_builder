import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_printers/printer_based_on_async_buffer.dart && ./example/logger_builder_examples/bin/async_printers/printer_based_on_async_buffer.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  final asyncPrinter1 = AsyncBuffer<String>((messages) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('1: Send messages: ${messages.length}');
    for (final message in messages) {
      print('1: $message');
    }
    return [];
  });

  log.printer = asyncPrinter1.publish;

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

  await asyncPrinter1.flush();

  final asyncPrinter2 = MyAsyncPrinter();

  log.printer = asyncPrinter2.publish;

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

  await asyncPrinter2.flush();

  print('end of main');
}

final class MyAsyncPrinter extends AsyncBufferBase<String> {
  MyAsyncPrinter();

  @override
  FutureOr<List<String>> handle(List<String> messages) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    print('2: Send messages: ${messages.length}');
    for (final message in messages) {
      print('2: $message');
    }
    return [];
  }
}
