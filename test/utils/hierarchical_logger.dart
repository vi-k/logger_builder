import 'dart:collection';

import 'package:logger_builder/logger_builder.dart';

typedef LogFunction =
    bool Function(Object? message, {Object? error, StackTrace? stackTrace});

final class LogEntry extends CustomLogEntry {
  final DateTime timestamp;
  final List<String> path;
  final LazyString _lazyMessage;

  LogEntry(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required this.path,
    required Object? message,
  }) : timestamp = DateTime.now(),
       _lazyMessage = LazyString(message);

  String get name => path.last;

  String? get message => _lazyMessage.value;
}

final class LevelLogger
    extends
        CustomLevelLogger<Logger, LevelLogger, LogFunction, LogEntry, String> {
  LevelLogger({required super.level, required super.name})
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
      path: logger.path,
      message: message,
    );

    printer(builder(entry));

    return true;
  };
}

final class Logger
    extends CustomLogger<Logger, LevelLogger, LogFunction, LogEntry, String> {
  final List<String> path;

  Logger(String name) : path = UnmodifiableListView(List.filled(1, name));

  Logger._(super.parent, String name)
    : path = UnmodifiableListView(
        List.generate(growable: false, parent.path.length + 1, (index) {
          if (index == parent.path.length) return name;
          return parent.path[index];
        }),
      ),
      super.sub();

  String get name => path.last;

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
      '[${entry.shortLevelName}] ${entry.path.join(' | ')} | ${entry.message}';
}
