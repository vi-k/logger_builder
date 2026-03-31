import 'dart:convert';

import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/json_reporter.dart';

final class DefaultJsonPublisher implements CustomLogPublisher<JsonReport> {
  const DefaultJsonPublisher();

  static Map<String, Object?> convertToJson(JsonReport report) {
    final json = <String, Object?>{
      'level': report.levelName,
      'timestamp': report.timestamp.microsecondsSinceEpoch,
      'event': report.event,
    };
    if (report.data is! JsonReportNoData) {
      json['data'] = report.data;
    }

    return json;
  }

  static String jsonToString(Map<String, Object?> json) => jsonEncode(
        json,
        toEncodable: (nonEncodable) {
          try {
            return (nonEncodable as dynamic).toJson();
            // ignore: avoid_catching_errors
          } on NoSuchMethodError {
            return nonEncodable.toString();
          }
        },
      );

  static String format(JsonReport report) =>
      jsonToString(convertToJson(report));

  static void output(String str) => print(str);

  @override
  void publish(JsonReport report) {
    output(format(report));
  }
}

final class EncodableClass {
  final int id;
  final String data;

  const EncodableClass(this.id, this.data);

  Map<String, Object?> toJson() => {'id': id, 'data': data};
}

final class NonEncodableClass {
  final int id;
  final String data;

  const NonEncodableClass(this.id, this.data);

  @override
  String toString() => '$NonEncodableClass(id: $id, data: $data)';
}

Future<void> main() async {
  final log = JsonReporter()
    ..level = Levels.debug
    ..publisher = const DefaultJsonPublisher();

  title('Custom printer, no data:');
  log[Levels.error].publisher = CustomLogFormatter(
    format: DefaultJsonPublisher.format,
    output: (str) => DefaultJsonPublisher.output('$fgRed$str$reset'),
  );
  log.d('debug-event');
  log.i('info-event');
  log.e('error-event');

  title('Data is null:');
  log.d('debug-event', data: null);
  log.i('info-event', data: null);
  log.e('error-event', data: null);

  title('Data is primitive value:');
  log.d('debug-event', data: 123);
  log.i('info-event', data: 'abc');
  log.e('error-event', data: true);

  title('Data is array (List):');
  log.d('debug-event', data: [1, 2, 3]);
  log.i('info-event', data: ['a', 'b', 'c']);
  log.e('error-event', data: [false, true, false]);

  title('Data is object (Map):');
  log.d('debug-event', data: {'id': 1, 'data': 'Debug data'});
  log.i('info-event', data: {'id': 2, 'data': 'Info data'});
  log.e('error-event', data: {'id': 3, 'data': 'Error data'});

  title('Data is encodable object (converted to Map):');
  log.d('debug-event', data: const EncodableClass(1, 'Debug data'));
  log.i('info-event', data: const EncodableClass(2, 'Info data'));
  log.e('error-event', data: const EncodableClass(3, 'Error data'));

  title('Data is non-encodable object (converted to String):');
  log.d('debug-event', data: const NonEncodableClass(1, 'Debug data'));
  log.i('info-event', data: const NonEncodableClass(2, 'Info data'));
  log.e('error-event', data: const NonEncodableClass(3, 'Error data'));

  title('Custom json builder:');
  String customBuilder(JsonReport report) {
    final json = DefaultJsonPublisher.convertToJson(report);
    json['additional_data'] = 42;
    return DefaultJsonPublisher.jsonToString(json);
  }

  log.publisher = CustomLogFormatter(
    format: customBuilder,
    output: DefaultJsonPublisher.output,
  );
  log[Levels.error].publisher = CustomLogFormatter(
    format: customBuilder,
    output: (str) => DefaultJsonPublisher.output('$fgRed$str$reset'),
  );
  log.d('debug-event', data: {'id': 1, 'data': 'Debug data'});
  log.i('info-event', data: {'id': 2, 'data': 'Info data'});
  log.e('error-event', data: {'id': 3, 'data': 'Error data'});
  log.publisher = const DefaultJsonPublisher();
}
