import 'package:logger_builder/logger_builder.dart';

typedef LogFn = bool Function(
  Object? source,
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
});

final class Log extends CustomLog {
  static int _lastSequenceNumber = 0;

  final DateTime time;
  final int sequenceNumber;
  final String name;
  final LazyStringOrNull _lazySource;
  final LazyStringOrNull _lazyMessage;

  Log(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    super.zone,
    required this.name,
    required Object? source,
    required Object? message,
  })  : time = DateTime.now(),
        sequenceNumber = ++_lastSequenceNumber,
        _lazySource = LazyStringOrNull(source),
        _lazyMessage = LazyStringOrNull(message);

  String? get source => _lazySource.value;
  String? get message => _lazyMessage.value;
}

final class LevelLogger
    extends CustomLevelLogger<Logger, LevelLogger, LogFn, Log> {
  LevelLogger({required super.level, required super.name, super.shortName})
      : super(
          noLog: (_, __, {error, stackTrace}) => true,
        );

  @override
  LogFn get processLog => (source, message, {error, stackTrace}) {
        publisher.publish(
          Log(
            this,
            error: error,
            stackTrace: stackTrace,
            name: logger.name,
            source: source,
            message: message,
          ),
        );

        return true;
      };
}

final class Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log> {
  final String name;

  Logger(this.name);

  @override
  void registerLevels() {
    registerLevel(_finest);
    registerLevel(_finer);
    registerLevel(_fine);
    registerLevel(_config);
    registerLevel(_info);
    registerLevel(_warning);
    registerLevel(_severe);
    registerLevel(_shout);
  }

  final LevelLogger _finest = LevelLogger(level: Levels.finest, name: 'FINEST');
  final LevelLogger _finer = LevelLogger(level: Levels.finer, name: 'FINER');
  final LevelLogger _fine = LevelLogger(level: Levels.fine, name: 'FINE');
  final LevelLogger _config = LevelLogger(level: Levels.config, name: 'CONFIG');
  final LevelLogger _info = LevelLogger(level: Levels.info, name: 'INFO');
  final LevelLogger _warning = LevelLogger(
    level: Levels.warning,
    name: 'WARNING',
  );
  final LevelLogger _severe = LevelLogger(level: Levels.severe, name: 'SEVERE');
  final LevelLogger _shout = LevelLogger(level: Levels.shout, name: 'SHOUT');

  LogFn get finest => _finest.log;
  LogFn get finer => _finer.log;
  LogFn get fine => _fine.log;
  LogFn get config => _config.log;
  LogFn get info => _info.log;
  LogFn get warning => _warning.log;
  LogFn get severe => _severe.log;
  LogFn get shout => _shout.log;

  static String defaultBuilder(Log entry) =>
      '${entry.time.toIso8601String()} [${entry.name}] '
      '#${entry.sequenceNumber} '
      '${entry.source == null ? '' : '${entry.source} | '}'
      '${entry.message}'
      '${entry.error == null ? '' : ': ${entry.error}'}'
      '${entry.stackTrace == null || entry.stackTrace == StackTrace.empty //
          ? '' : '\n${entry.stackTrace}'}';
}
