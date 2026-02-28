import 'package:logger_builder/logger_builder.dart';

typedef LogFunction = bool Function(Object? message,
    {Object? error, StackTrace? stackTrace});

final class LogEntry extends CustomLogEntry {
  final LazyStringOrNull _lazyMessage;

  LogEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required Object? message,
  }) : _lazyMessage = LazyStringOrNull(message);

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
          message: message,
        );

        printer(builder(entry));

        return true;
      };
}

final class Logger
    extends CustomLogger<Logger, LevelLogger, LogFunction, LogEntry, String> {
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

  LogFunction get d => _d.log;
  LogFunction get i => _i.log;
  LogFunction get e => _e.log;

  static String defaultBuilder(LogEntry entry) =>
      '[${entry.shortLevelName}] ${entry.message}';
}
