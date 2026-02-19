import 'dart:collection';

import 'package:logger_builder/logger_builder.dart';

typedef HierarchicalLog =
    bool Function(Object? message, {Object? error, StackTrace? stackTrace});

final class HierarchicalLogEntry extends CustomLogEntry {
  final DateTime timestamp;
  final List<String> path;
  final LazyString _lazyMessage;

  HierarchicalLogEntry(
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

final class HierarchicalLogger
    extends
        CustomLogger<
          HierarchicalLogger,
          HierarchicalLevelLogger,
          HierarchicalLog,
          HierarchicalLogEntry,
          String
        > {
  final List<String> path;

  HierarchicalLogger(String name)
    : path = UnmodifiableListView(List.filled(1, name));

  HierarchicalLogger._(super.parent, String name)
    : path = UnmodifiableListView(
        List.generate(growable: false, parent.path.length + 1, (index) {
          if (index == parent.path.length) return name;
          return parent.path[index];
        }),
      ),
      super.sub();

  String get name => path.last;

  HierarchicalLogger withAddedName(String name) =>
      HierarchicalLogger._(this, name);

  final HierarchicalLevelLogger _d = HierarchicalLevelLogger(
    level: Levels.debug,
    name: 'debug',
  );
  final HierarchicalLevelLogger _i = HierarchicalLevelLogger(
    level: Levels.info,
    name: 'info',
  );
  final HierarchicalLevelLogger _e = HierarchicalLevelLogger(
    level: Levels.error,
    name: 'error',
  );

  HierarchicalLog get d => _d.log;
  HierarchicalLog get i => _i.log;
  HierarchicalLog get e => _e.log;

  @override
  void registerLevels() {
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  static bool _noLog(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) => true;

  static String defaultBuilder(HierarchicalLogEntry entry) =>
      '[${entry.shortLevelName}] ${entry.path.join(' | ')} | ${entry.message}';
}

final class HierarchicalLevelLogger
    extends
        CustomLevelLogger<
          HierarchicalLogger,
          HierarchicalLevelLogger,
          HierarchicalLog,
          HierarchicalLogEntry,
          String
        > {
  HierarchicalLevelLogger({required super.level, required super.name})
    : super(
        noLog: HierarchicalLogger._noLog,
        builder: HierarchicalLogger.defaultBuilder,
        printer: print,
      );

  @override
  HierarchicalLog get processLog => (message, {error, stackTrace}) {
    if (!isEnabled) return true;

    final entry = HierarchicalLogEntry(
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
