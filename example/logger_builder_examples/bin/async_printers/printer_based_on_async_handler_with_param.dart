import 'dart:async';

import 'package:ansi_escape_codes/style.dart' as ansi;
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/simple_logger.dart';

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_printers/printer_based_on_async_handler_with_param.dart && ./example/logger_builder_examples/bin/async_printers/printer_based_on_async_handler_with_param.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  final asyncPrinter1 =
      AsyncHandlerWithParam<String, bool>((message, isError) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (isError) {
      print(ansi.red('1: $message'));
    } else {
      print('1: $message');
    }
  });

  log
    ..printer = asyncPrinter1.publishWithParam(false)
    ..[Levels.error].printer = asyncPrinter1.publishWithParam(true);

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPrinter1.flush();

  final asyncPrinter2 = MyAsyncPrinter();

  log
    ..printer = asyncPrinter2.publishWithParam(false)
    ..[Levels.error].printer = asyncPrinter2.publishWithParam(true);

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPrinter2.flush();

  print('end of main');
}

final class MyAsyncPrinter extends AsyncHandlerWithParamBase<String, bool> {
  final _errorPrinter = ansi.Printer(defaultStyle: ansi.red);
  final _normalPrinter = ansi.Printer();

  MyAsyncPrinter();

  @override
  FutureOr<void> handle(String message, bool isError) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (isError) {
      _errorPrinter.print('2: $message');
    } else {
      _normalPrinter.print('2: $message');
    }
  }
}
