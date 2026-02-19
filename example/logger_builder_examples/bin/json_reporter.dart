import 'dart:convert';

import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/json_reporter.dart';

Future<void> main() async {
  final log = JsonReporter()..level = Levels.debug;

  title('Default usage:');
  log.d('debug-event', {'id': 1, 'data': 'Debug data'});
  log.i('info-event', {'id': 2, 'data': 'Info data'});
  log.e('error-event', {'id': 3, 'data': 'Error data'});

  title('level = Level.info:');
  log.level = Levels.info;
  log.d('debug-event', {'id': 1, 'data': 'Debug data'});
  log.i('info-event', {'id': 2, 'data': 'Info data'});
  log.e('error-event', {'id': 3, 'data': 'Error data'});

  title('level = Level.error:');
  log.level = Levels.error;
  log.d('debug-event', {'id': 1, 'data': 'Debug data'});
  log.i('info-event', {'id': 2, 'data': 'Info data'});
  log.e('error-event', {'id': 3, 'data': 'Error data'});
  log.level = Levels.all;

  title('Access to level logger:');
  log[Levels.info].log('info-event', {'id': 1, 'data': 'Info data'});

  title('Custom builder:');
  log.builder =
      (entry) => JsonReporter.defaultBuilder(entry)..['additional_data'] = 42;
  log.d('debug-event', {'id': 1, 'data': 'Debug data'});
  log.i('info-event', {'id': 2, 'data': 'Info data'});
  log.e('error-event', {'id': 3, 'data': 'Error data'});
  log.builder = JsonReporter.defaultBuilder;

  title('Custom printer:');
  log[Levels.error].printer =
      (text) => print('\x1B[31m${jsonEncode(text)}\x1B[0m');
  log.d('debug-event', {'id': 1, 'data': 'Debug data'});
  log.i('info-event', {'id': 2, 'data': 'Info data'});
  log.e('error-event', {'id': 3, 'data': 'Error data'});
  log.printer = JsonReporter.defaultPrinter;
}
