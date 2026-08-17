import 'package:logger_builder/logger_builder.dart';

typedef LogFn = bool Function(
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
});

final class Log extends CustomLog {
  final DateTime timestamp;
  final LazyString _lazyPath;
  final LazyStringOrNull _lazyMessage;

  Log(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required LazyString path,
    required Object? message,
  })  : timestamp = DateTime.now(),
        _lazyPath = path,
        _lazyMessage = LazyStringOrNull(message);

  // ignore: use_super_parameters
  Log.copy(
    Log original, {
    Object? message,
    Object? error,
    StackTrace? stackTrace,
  })  : timestamp = original.timestamp,
        _lazyPath = original._lazyPath,
        _lazyMessage =
            message != null ? LazyStringOrNull(message) : original._lazyMessage,
        super.copy(
          original,
          error: error,
          stackTrace: stackTrace,
        );

  String get path => _lazyPath.value;
  String? get message => _lazyMessage.value;
}

final class LevelLogger
    extends CustomLevelLogger<Logger, LevelLogger, LogFn, Log> {
  LevelLogger({required super.level, required super.name, super.shortName})
      : super(
          noLog: (_, {error, stackTrace}) => true,
        );

  @override
  LogFn get processLog => (message, {error, stackTrace}) {
        publishLog(
          Log(
            this,
            error: error,
            stackTrace: stackTrace,
            path: logger._lazyPath,
            message: message,
          ),
        );

        return true;
      };
}

final class Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log> {
  final LazyString _lazyPath;
  final String pathSeparator;

  Logger(Object name, {this.pathSeparator = ' | '})
      : _lazyPath = LazyString(name);

  Logger._(super.parent, Object name)
      : _lazyPath = LazyString(
          () => '${parent.path}'
              '${parent.pathSeparator}'
              '${LazyString(name).value}',
        ),
        pathSeparator = parent.pathSeparator,
        super.sub();

  String get path => _lazyPath.value;

  Logger withAddedName(String name) => Logger._(this, name);

  final LevelLogger _d = LevelLogger(level: Levels.debug, name: 'debug');
  final LevelLogger _i = LevelLogger(level: Levels.info, name: 'info');
  final LevelLogger _e = LevelLogger(level: Levels.error, name: 'error');

  LogFn get d => _d.log;
  LogFn get i => _i.log;
  LogFn get e => _e.log;

  @override
  void registerLevels() {
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  static String defaultFormat(Log log) =>
      '[${log.shortLevelName}] ${log.path} | ${log.message}';
}
