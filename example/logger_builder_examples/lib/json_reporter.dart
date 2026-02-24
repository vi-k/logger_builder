import 'dart:convert';

import 'package:logger_builder/logger_builder.dart';

final class JsonReportNoData {
  const JsonReportNoData._();

  @override
  String toString() => 'no data';
}

const _noData = JsonReportNoData._();

typedef JsonReport =
    bool Function(
      String event, {
      Object? data,
      Object? error,
      StackTrace? stackTrace,
    });

final class JsonReportEntry extends CustomLogEntry {
  final DateTime timestamp;
  final String event;
  final Lazy _lazyData;

  JsonReportEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required this.event,
    required Object? data,
  }) : timestamp = DateTime.now(),
       _lazyData = Lazy(data);

  Object? get data => _lazyData.resolved;
}

final class JsonLevelReporter
    extends
        CustomLevelLogger<
          JsonReporter,
          JsonLevelReporter,
          JsonReport,
          JsonReportEntry,
          Map<String, Object?>
        > {
  JsonLevelReporter({
    required super.level,
    required super.name,
    super.shortName,
  }) : super(
         noLog: (_, {data = _noData, error, stackTrace}) => true,
         builder: JsonReporter.defaultBuilder,
         printer: JsonReporter.defaultPrinter,
       );

  @override
  JsonReport get processLog => (event, {data = _noData, error, stackTrace}) {
    final entry = JsonReportEntry(
      this,
      error: error,
      stackTrace: stackTrace,
      event: event,
      data: data,
    );

    printer(builder(entry));

    return true;
  };
}

final class JsonReporter
    extends
        CustomLogger<
          JsonReporter,
          JsonLevelReporter,
          JsonReport,
          JsonReportEntry,
          Map<String, Object?>
        > {
  JsonReporter();

  final JsonLevelReporter _d = JsonLevelReporter(
    level: Levels.debug,
    name: 'debug',
  );
  final JsonLevelReporter _i = JsonLevelReporter(
    level: Levels.info,
    name: 'info',
  );
  final JsonLevelReporter _e = JsonLevelReporter(
    level: Levels.error,
    name: 'error',
  );

  JsonReport get d => _d.log;
  JsonReport get i => _i.log;
  JsonReport get e => _e.log;

  @override
  void registerLevels() {
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  static Map<String, Object?> defaultBuilder(JsonReportEntry entry) {
    final json = <String, Object?>{
      'level': entry.levelName,
      'timestamp': entry.timestamp.microsecondsSinceEpoch,
      'event': entry.event,
    };
    if (entry.data is! JsonReportNoData) {
      json['data'] = entry.data;
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

  static void defaultPrinter(Map<String, Object?> json) {
    print(jsonToString(json));
  }
}
