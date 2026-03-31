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

/// Usage:
///
/// ```bash
/// dart compile exe example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer_and_param.dart && ./example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer_and_param.exe
/// ```
Future<void> main() async {
  final log = Logger()..level = Levels.all;

  title('AsyncPublisherWithBufferAndParamBase');

  final myAsyncPublisher = MyAsyncPublisher();
  log.publisher = myAsyncPublisher.withParam(false);
  log[Levels.error].publisher = myAsyncPublisher.withParam(true);

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

  title('AsyncPublisherWithBufferAndParam');

  final asyncPublisher =
      AsyncPublisherWithBufferAndParam<bool, Log>((entries, _) async {
    description('Handle ${entries.length} message(s)');
    for (final (isError, log) in entries) {
      final str = await defaultAsyncFormat(isError, log);
      await defaultAsyncOutput(isError, str);
    }
  });

  log.publisher = asyncPublisher.withParam(false);
  log[Levels.error].publisher = asyncPublisher.withParam(true);

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

  title('AsyncFormatterWithBufferAndParam');

  final asyncFormatter =
      AsyncFormatterWithBufferAndParam<bool, Log, List<(bool, String)>>(
    format: (entries, retryBuffer) async {
      description('Format ${entries.length} message(s)');
      try {
        // Formatting in parallel.
        final outs =
            await entries.map((e) => defaultAsyncFormat(e.$1, e.$2)).wait;
        return outs.indexed.map((e) => (entries[e.$1].$1, e.$2)).toList();
      } on Object {
        retryBuffer.addAll(entries);
        return [];
      }
    },
    output: (out, entries, retryBuffer) async {
      description('Output ${out.length} message(s)');
      try {
        // Output sequentially.
        for (final (isError, str) in out) {
          await defaultAsyncOutput(isError, str);
        }
      } on Object {
        retryBuffer.addAll(entries);
      }
    },
  );

  log.publisher = asyncFormatter.withParam(false);
  log[Levels.error].publisher = asyncFormatter.withParam(true);

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

final class MyAsyncPublisher
    extends AsyncPublisherWithBufferAndParamBase<bool, Log> {
  MyAsyncPublisher();

  @override
  FutureOr<void> handle(
    List<(bool, Log)> logs,
    List<(bool, Log)> retryBuffer,
  ) async {
    description('Handle ${logs.length} message(s)');
    for (final (isError, log) in logs) {
      final str = await defaultAsyncFormat(isError, log);
      await defaultAsyncOutput(isError, str);
    }
  }
}
