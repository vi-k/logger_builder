import 'package:logger_builder/logger_builder.dart';

typedef LogFunction = bool Function(
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
});

final class LogEntry extends CustomLogEntry {
  final DateTime timestamp;
  final LazyString _lazyPath;
  final LazyStringOrNull _lazyMessage;

  LogEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required LazyString path,
    required Object? message,
  })  : timestamp = DateTime.now(),
        _lazyPath = path,
        _lazyMessage = LazyStringOrNull(message);

  String get path => _lazyPath.value;
  String? get message => _lazyMessage.value;
}

final class LevelLogger extends CustomLevelLogger<Logger, LevelLogger,
    LogFunction, LogEntry, String> {
  LevelLogger({required super.level, required super.name, super.shortName})
      : super(
          noLog: (_, {error, stackTrace}) => true,
          builder: Logger.defaultBuilder,
          printer: print,
        );

  @override
  LogFunction get processLog => (message, {error, stackTrace}) {
        final entry = LogEntry(
          this,
          error: error,
          stackTrace: stackTrace,
          path: logger._lazyPath,
          message: message,
        );

        printer(builder(entry));

        return true;
      };
}

final class Logger
    extends CustomLogger<Logger, LevelLogger, LogFunction, LogEntry, String> {
  final LazyString _lazyPath;
  final String pathSeparator;

  Logger(Object name, {this.pathSeparator = ' | '})
      : _lazyPath = LazyString(name, '?');

  Logger._(super.parent, Object name)
      : _lazyPath = LazyString(
          () => '${parent.path}'
              '${parent.pathSeparator}'
              '${LazyString(name, '?').value}',
        ),
        pathSeparator = parent.pathSeparator,
        super.sub();

  String get path => _lazyPath.value;

  Logger withAddedName(String name) => Logger._(this, name);

  final LevelLogger _d = LevelLogger(level: Levels.debug, name: 'debug');
  final LevelLogger _i = LevelLogger(level: Levels.info, name: 'info');
  final LevelLogger _e = LevelLogger(level: Levels.error, name: 'error');

  LogFunction get d => _d.log;
  LogFunction get i => _i.log;
  LogFunction get e => _e.log;

  @override
  void registerLevels() {
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  static String defaultBuilder(LogEntry entry) =>
      '[${entry.shortLevelName}] ${entry.path} | ${entry.message}';
}
