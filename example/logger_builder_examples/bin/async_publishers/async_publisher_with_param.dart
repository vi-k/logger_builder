import 'dart:async';

import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<String> defaultAsyncFormat(bool isError, Log log) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return '${isError ? '‼ ' : '  '}[${log.shortLevelName}] ${log.message}';
}

Future<void> defaultAsyncOutput(bool isError, String str) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  print(isError ? '$fgRed$str$reset' : str);
}

Future<void> main() async {
  final log = Logger()..level = Levels.all;

  title('AsyncPublisherWithParamBase');

  // When different formatting is required, it’s tempting to create a separate
  // publisher for each case, as we would in the synchronous version. But then
  // the publishers wouldn’t be synchronized with each other. That’s why we
  // need a single publisher, but one that allows us to pass different
  // parameters to the handler function.

  final myAsyncPublisher = MyAsyncPublisher();
  log.publisher = myAsyncPublisher.withParam(false);
  log[Levels.error].publisher = myAsyncPublisher.withParam(true);

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await myAsyncPublisher.flush();

  title('AsyncPublisherWithParam');

  final asyncPublisher =
      AsyncPublisherWithParam<bool, Log>((isError, log) async {
    final str = await defaultAsyncFormat(isError, log);
    await defaultAsyncOutput(isError, str);
  });
  log.publisher = asyncPublisher.withParam(false);
  log[Levels.error].publisher = asyncPublisher.withParam(true);

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPublisher.flush();

  title('AsyncFormatterWithParam');

  final asyncFormatter = AsyncFormatterWithParam<bool, Log, String>(
    format: defaultAsyncFormat,
    output: defaultAsyncOutput,
  );
  log.publisher = asyncFormatter.withParam(false);
  log[Levels.error].publisher = asyncFormatter.withParam(true);

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncFormatter.flush();

  title('end of main');
}

final class MyAsyncPublisher extends AsyncPublisherWithParamBase<bool, Log> {
  @override
  FutureOr<void> handle(bool param, Log log) async {
    final str = await defaultAsyncFormat(param, log);
    await defaultAsyncOutput(param, str);
  }
}
