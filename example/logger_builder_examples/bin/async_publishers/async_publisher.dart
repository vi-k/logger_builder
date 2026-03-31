import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<String> defaultAsyncFormat(Log log) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  return '[${log.shortLevelName}] ${log.message}';
}

Future<void> defaultAsyncOutput(String str) async {
  await Future<void>.delayed(const Duration(milliseconds: 10));
  print(str);
}

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_publishers/async_publisher.dart && ./example/logger_builder_examples/bin/async_publishers/async_publisher.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  title('AsyncPublisherBase');

  final myAsyncPublisher = MyAsyncPublisher();
  log.publisher = myAsyncPublisher;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await myAsyncPublisher.flush();

  title('AsyncPublisher');

  final asyncPublisher = AsyncPublisher<Log>((log) async {
    final str = await defaultAsyncFormat(log);
    await defaultAsyncOutput(str);
  });
  log.publisher = asyncPublisher;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPublisher.flush();

  title('AsyncFormatter');

  final asyncFormatter = AsyncFormatter<Log, String>(
    format: defaultAsyncFormat,
    output: defaultAsyncOutput,
  );
  log.publisher = asyncFormatter;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncFormatter.flush();

  title('end of main');
}

final class MyAsyncPublisher extends AsyncPublisherBase<Log> {
  @override
  FutureOr<void> handle(Log log) async {
    final str = await defaultAsyncFormat(log);
    await defaultAsyncOutput(str);
  }
}
