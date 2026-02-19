import 'package:logger_builder/logger_builder.dart';

typedef ComplexLog =
    bool Function(
      Object? source,
      Object? message, {
      Object? error,
      StackTrace? stackTrace,
    });

final class ComplexLogEntry extends CustomLogEntry {
  static int _lastSequenceNumber = 0;

  final DateTime time;
  final int sequenceNumber;
  final String name;
  final LazyString _lazySource;
  final LazyString _lazyMessage;

  ComplexLogEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    super.zone,
    required this.name,
    required Object? source,
    required Object? message,
  }) : time = DateTime.now(),
       sequenceNumber = ++_lastSequenceNumber,
       _lazySource = LazyString(source),
       _lazyMessage = LazyString(message);

  String? get source => _lazySource.value;
  String? get message => _lazyMessage.value;
}

final class ComplexLogger
    extends
        CustomLogger<
          ComplexLogger,
          ComplexLevelLogger,
          ComplexLog,
          ComplexLogEntry,
          String
        > {
  final String name;

  ComplexLogger(this.name);

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

  final ComplexLevelLogger _finest = ComplexLevelLogger(
    level: Levels.finest,
    name: 'FINEST',
  );
  final ComplexLevelLogger _finer = ComplexLevelLogger(
    level: Levels.finer,
    name: 'FINER',
  );
  final ComplexLevelLogger _fine = ComplexLevelLogger(
    level: Levels.fine,
    name: 'FINE',
  );
  final ComplexLevelLogger _config = ComplexLevelLogger(
    level: Levels.config,
    name: 'CONFIG',
  );
  final ComplexLevelLogger _info = ComplexLevelLogger(
    level: Levels.info,
    name: 'INFO',
  );
  final ComplexLevelLogger _warning = ComplexLevelLogger(
    level: Levels.warning,
    name: 'WARNING',
  );
  final ComplexLevelLogger _severe = ComplexLevelLogger(
    level: Levels.severe,
    name: 'SEVERE',
  );
  final ComplexLevelLogger _shout = ComplexLevelLogger(
    level: Levels.shout,
    name: 'SHOUT',
  );

  ComplexLog get finest => _finest.log;
  ComplexLog get finer => _finer.log;
  ComplexLog get fine => _fine.log;
  ComplexLog get config => _config.log;
  ComplexLog get info => _info.log;
  ComplexLog get warning => _warning.log;
  ComplexLog get severe => _severe.log;
  ComplexLog get shout => _shout.log;

  static bool _noLog(
    Object? source,
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) => true;

  static String defaultBuilder(ComplexLogEntry entry) =>
      '${entry.time.toIso8601String()} [${entry.name}] '
      '#${entry.sequenceNumber} '
      '${entry.source == null ? '' : '${entry.source} | '}'
      '${entry.message}'
      '${entry.error == null ? '' : ': ${entry.error}'}'
      '${entry.stackTrace == null || entry.stackTrace == StackTrace.empty //
                  ? '' : '\n${entry.stackTrace}'}';
}

final class ComplexLevelLogger
    extends
        CustomLevelLogger<
          ComplexLogger,
          ComplexLevelLogger,
          ComplexLog,
          ComplexLogEntry,
          String
        > {
  ComplexLevelLogger({
    required super.level,
    required super.name,
    super.shortName,
  }) : super(
         noLog: ComplexLogger._noLog,
         builder: ComplexLogger.defaultBuilder,
         printer: print,
       );

  @override
  ComplexLog get processLog => (source, message, {error, stackTrace}) {
    if (!isEnabled) return true;

    final entry = ComplexLogEntry(
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
