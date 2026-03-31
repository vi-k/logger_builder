import 'package:logger_builder/logger_builder.dart';

typedef LogFn = bool Function(
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
});

final class Log extends CustomLog {
  final LazyString _lazyMessage;

  Log(
    super.levelLogger, {
    required Object? message,
    super.error,
    super.stackTrace,
    super.zone,
  }) : _lazyMessage = LazyString(message);

  String get message => _lazyMessage.value;
}

final class LevelLogger
    extends CustomLevelLogger<Logger, LevelLogger, LogFn, Log> {
  LevelLogger({required super.level, required super.name, super.shortName})
      : super(
          noLog: (_, {error, stackTrace}) => true,
        );

  @override
  LogFn get processLog => (message, {error, stackTrace}) {
        publisher.publish(
          Log(
            this,
            message: message,
            error: error,
            stackTrace: stackTrace,
          ),
        );

        return true;
      };
}

final class Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log> {
  Logger();

  @override
  void registerLevels() {
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  final LevelLogger _d = LevelLogger(level: Levels.debug, name: 'debug');
  final LevelLogger _i = LevelLogger(level: Levels.info, name: 'info');
  final LevelLogger _e = LevelLogger(level: Levels.error, name: 'error');

  LogFn get d => _d.log;
  LogFn get i => _i.log;
  LogFn get e => _e.log;
}
