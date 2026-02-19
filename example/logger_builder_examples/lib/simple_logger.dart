import 'package:logger_builder/logger_builder.dart';

typedef SimpleLog =
    bool Function(Object? message, {Object? error, StackTrace? stackTrace});

final class SimpleLogEntry extends CustomLogEntry {
  final LazyString _lazyMessage;

  SimpleLogEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required Object? message,
  }) : _lazyMessage = LazyString(message);

  String? get message => _lazyMessage.value;
}

final class SimpleLogger
    extends
        CustomLogger<
          SimpleLogger,
          SimpleLevelLogger,
          SimpleLog,
          SimpleLogEntry,
          String
        > {
  SimpleLogger();

  @override
  void registerLevels() {
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  final SimpleLevelLogger _d = SimpleLevelLogger(
    level: Levels.debug,
    name: 'debug',
  );
  final SimpleLevelLogger _i = SimpleLevelLogger(
    level: Levels.info,
    name: 'info',
  );
  final SimpleLevelLogger _e = SimpleLevelLogger(
    level: Levels.error,
    name: 'error',
  );

  SimpleLog get d => _d.log;
  SimpleLog get i => _i.log;
  SimpleLog get e => _e.log;

  static bool _noLog(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) => true;

  static String defaultBuilder(SimpleLogEntry entry) =>
      '[${entry.shortLevelName}] ${entry.message}';
}

final class SimpleLevelLogger
    extends
        CustomLevelLogger<
          SimpleLogger,
          SimpleLevelLogger,
          SimpleLog,
          SimpleLogEntry,
          String
        > {
  SimpleLevelLogger({
    required super.level,
    required super.name,
    super.shortName,
  }) : super(
         noLog: SimpleLogger._noLog,
         builder: SimpleLogger.defaultBuilder,
         printer: print,
       );

  @override
  SimpleLog get processLog => (message, {error, stackTrace}) {
    if (!isEnabled) return true;

    final entry = SimpleLogEntry(
      this,
      error: error,
      stackTrace: stackTrace,
      message: message,
    );

    printer(builder(entry));

    return true;
  };
}
