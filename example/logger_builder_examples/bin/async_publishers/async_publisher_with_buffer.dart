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
/// dart compile exe example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer.dart && ./example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  title('AsyncPublisherWithBufferBase');

  final myAsyncPublisher = MyAsyncPublisher();
  log.publisher = myAsyncPublisher;

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

  await myAsyncPublisher.flush();

  title('AsyncPublisherWithBuffer');

  final asyncPublisher = AsyncPublisherWithBuffer<Log>((logs, _) async {
    description('Handle ${logs.length} message(s)');
    for (final log in logs) {
      final str = await defaultAsyncFormat(log);
      await defaultAsyncOutput(str);
    }
  });

  log.publisher = asyncPublisher;

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

  await asyncPublisher.flush();

  title('AsyncFormatterWithBuffer');

  final asyncFormatter = AsyncFormatterWithBuffer<Log, List<String>>(
    format: (logs, retryBuffer) async {
      description('Format ${logs.length} message(s)');
      try {
        // Formatting in parallel.
        return logs.map(defaultAsyncFormat).wait;
      } on Object {
        retryBuffer.addAll(logs);
        return [];
      }
    },
    output: (out, logs, retryBuffer) async {
      description('Output ${out.length} message(s)');
      try {
        // Output sequentially.
        for (final str in out) {
          await defaultAsyncOutput(str);
        }
      } on Object {
        retryBuffer.addAll(logs);
      }
    },
  );

  log.publisher = asyncFormatter;

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

  await asyncFormatter.flush();

  title('end of main');
}

final class MyAsyncPublisher extends AsyncPublisherWithBufferBase<Log> {
  MyAsyncPublisher();

  @override
  FutureOr<void> handle(List<Log> logs, List<Log> retryBuffer) async {
    description('Handle ${logs.length} message(s)');
    for (final log in logs) {
      final str = await defaultAsyncFormat(log);
      await defaultAsyncOutput(str);
    }
  }
}
