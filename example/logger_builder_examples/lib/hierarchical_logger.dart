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
    : // - Используем `UnmodifiableListView`, чтобы предотвратить изменение
      //   пути. Соответственно, при передаче пути в `LogEntry` не нужно будет
      //   делать копию списка: экономим и на скорости, и на памяти.
      // - Список из одного элемента создаём с помощью  `List.filled`, т.к. это
      //   быстрее и экономичнее, чем вариант `[name]`.
      // - `UnmodifiableListView` используем вместо `List.unmodifiable`, чтобы
      //   лишний раз не делать копию списка: экономим и на скорости, и на
      //   памяти. Но это возможно только в случае, когда точно знаем, что
      //   исходный список не будет меняться.
      path = UnmodifiableListView(List.filled(1, name));

  HierarchicalLogger._(super.parent, String name)
    : // - Используем `UnmodifiableListView`, чтобы предотвратить изменение пути.
      //   Соответственно, при передаче пути в LogEntry не нужно будет делать
      //   копию списка: экономим и на скорости, и на памяти.
      // - Новый список (копия списка родителя + имя текущего логгера) создаём
      //   с помощью `List.generate` с `growable: false`, т.к. это
      //   гораздо быстрее и экономичнее, чем вариант [name].
      // - UnmodifiableListView используем вместо List.unmodifiable, чтобы не
      //   делать копию списка: экономим и на скорости, и на памяти. Но это
      //   возможно только в случае, когда точно знаем, что исходный список не
      //   будет меняться.
      path = UnmodifiableListView(
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
    shortName: 'd',
  );
  final HierarchicalLevelLogger _i = HierarchicalLevelLogger(
    level: Levels.info,
    name: 'info',
    shortName: 'i',
  );
  final HierarchicalLevelLogger _e = HierarchicalLevelLogger(
    level: Levels.error,
    name: 'error',
    shortName: 'e',
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
  HierarchicalLevelLogger({
    required super.level,
    required super.name,
    required super.shortName,
  }) : super(
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
