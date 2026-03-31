import 'package:logger_builder/logger_builder.dart';

final class JsonReportNoData {
  const JsonReportNoData._();

  @override
  String toString() => 'no data';
}

const _noData = JsonReportNoData._();

typedef JsonReporterFn = bool Function(
  String event, {
  Object? data,
  Object? error,
  StackTrace? stackTrace,
});

final class JsonReport extends CustomLog {
  final DateTime timestamp;
  final String event;
  final Lazy _lazyData;

  JsonReport(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required this.event,
    required Object? data,
  })  : timestamp = DateTime.now(),
        _lazyData = Lazy(data);

  Object? get data => _lazyData.resolved;
}

final class JsonLevelReporter extends CustomLevelLogger<JsonReporter,
    JsonLevelReporter, JsonReporterFn, JsonReport> {
  JsonLevelReporter({
    required super.level,
    required super.name,
    super.shortName,
  }) : super(
          noLog: (_, {data, error, stackTrace}) => true,
        );

  @override
  JsonReporterFn get processLog =>
      (event, {data = _noData, error, stackTrace}) {
        publisher.publish(
          JsonReport(
            this,
            error: error,
            stackTrace: stackTrace,
            event: event,
            data: data,
          ),
        );

        return true;
      };
}

final class JsonReporter extends CustomLogger<JsonReporter, JsonLevelReporter,
    JsonReporterFn, JsonReport> {
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

  JsonReporterFn get d => _d.log;
  JsonReporterFn get i => _i.log;
  JsonReporterFn get e => _e.log;

  @override
  void registerLevels() {
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }
}
