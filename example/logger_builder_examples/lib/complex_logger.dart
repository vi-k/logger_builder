import 'package:logger_builder/logger_builder.dart';

typedef LogFunction = bool Function(
  Object? source,
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
});

final class LogEntry extends CustomLogEntry {
  static int _lastSequenceNumber = 0;

  final DateTime time;
  final int sequenceNumber;
  final String name;
  final LazyString _lazySource;
  final LazyString _lazyMessage;

  LogEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    super.zone,
    required this.name,
    required Object? source,
    required Object? message,
  })  : time = DateTime.now(),
        sequenceNumber = ++_lastSequenceNumber,
        _lazySource = LazyString(source),
        _lazyMessage = LazyString(message);

  String? get source => _lazySource.value;
  String? get message => _lazyMessage.value;
}

final class LevelLogger extends CustomLevelLogger<Logger, LevelLogger,
    LogFunction, LogEntry, String> {
  LevelLogger({required super.level, required super.name, super.shortName})
      : super(
          noLog: (_, __, {error, stackTrace}) => true,
          builder: Logger.defaultBuilder,
          printer: print,
        );

  @override
  LogFunction get processLog => (source, message, {error, stackTrace}) {
        final entry = LogEntry(
          this,
          error: error,
          stackTrace: stackTrace,
          name: logger.name,
          source: source,
          message: message,
        );

        printer(builder(entry));

        return true;
      };
}

final class Logger
    extends CustomLogger<Logger, LevelLogger, LogFunction, LogEntry, String> {
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

  LogFunction get finest => _finest.log;
  LogFunction get finer => _finer.log;
  LogFunction get fine => _fine.log;
  LogFunction get config => _config.log;
  LogFunction get info => _info.log;
  LogFunction get warning => _warning.log;
  LogFunction get severe => _severe.log;
  LogFunction get shout => _shout.log;

  static String defaultBuilder(LogEntry entry) =>
      '${entry.time.toIso8601String()} [${entry.name}] '
      '#${entry.sequenceNumber} '
      '${entry.source == null ? '' : '${entry.source} | '}'
      '${entry.message}'
      '${entry.error == null ? '' : ': ${entry.error}'}'
      '${entry.stackTrace == null || entry.stackTrace == StackTrace.empty //
          ? '' : '\n${entry.stackTrace}'}';
}
