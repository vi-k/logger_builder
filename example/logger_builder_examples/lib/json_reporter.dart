import 'dart:convert';

import 'package:logger_builder/logger_builder.dart';

typedef JsonReport =
    bool Function(
      String event,
      Object json, {
      Object? error,
      StackTrace? stackTrace,
    });

final class LazyJson extends TypedLazy<Map<String, Object?>> {
  LazyJson(super.unresolved);

  @override
  Map<String, Object?> convert(Object? resolved) => switch (resolved) {
    Map<String, Object?>() => resolved,
    _ =>
      throw ArgumentError('Expected a Map<String, Object?> but got $resolved'),
  };
}

final class JsonReportEntry extends CustomLogEntry {
  final DateTime timestamp;
  final String event;
  final LazyJson _lazyJson;

  JsonReportEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required this.event,
    required Object? json,
  }) : timestamp = DateTime.now(),
       _lazyJson = LazyJson(json);

  Map<String, Object?> get json => _lazyJson.value;
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
    shortName: 'd',
  );
  final JsonLevelReporter _i = JsonLevelReporter(
    level: Levels.info,
    name: 'info',
    shortName: 'i',
  );
  final JsonLevelReporter _e = JsonLevelReporter(
    level: Levels.error,
    name: 'error',
    shortName: 'e',
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

  static bool _noReport(
    String event,
    Object? json, {
    Object? error,
    StackTrace? stackTrace,
  }) => true;

  static Map<String, Object?> defaultBuilder(JsonReportEntry entry) {
    final json = <String, Object?>{
      'level': entry.levelName,
      'timestamp': entry.timestamp.microsecondsSinceEpoch,
      'event': entry.event,
      'data': entry.json,
    };
    return json;
  }

  static void defaultPrinter(Map<String, Object?> json) {
    print(jsonEncode(json));
  }
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
    required super.shortName,
  }) : super(
         noLog: JsonReporter._noReport,
         builder: JsonReporter.defaultBuilder,
         printer: JsonReporter.defaultPrinter,
       );

  @override
  JsonReport get processLog => (event, json, {error, stackTrace}) {
    if (!isEnabled) return true;

    final entry = JsonReportEntry(
      this,
      error: error,
      stackTrace: stackTrace,
      event: event,
      json: json,
    );

    printer(builder(entry));

    return true;
  };
}
