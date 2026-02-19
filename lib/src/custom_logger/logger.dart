import 'package:meta/meta.dart';

import 'entry.dart';
import 'levels.dart';

part 'level_logger.dart';

typedef CustomLogBuilder<Ent extends CustomLogEntry, Out extends Object?> =
    Out Function(Ent entry);

typedef CustomLogPrinter<Out extends Object?> = void Function(Out out);

abstract base class CustomLogger<
  L extends CustomLogger<L, LL, Log, Ent, Out>,
  LL extends CustomLevelLogger<L, LL, Log, Ent, Out>,
  Log extends Function,
  Ent extends CustomLogEntry,
  Out extends Object?
> {
  static final Finalizer<CustomLogger> _finalizer = Finalizer((logger) {
    logger._subloggers.removeWhere((subLogger) => subLogger.target == null);
  });

  int _level = Levels.off;
  final Map<int, LL> _levelLoggers = {};
  final List<WeakReference<L>> _subloggers = [];
  bool _levelLinked = false;
  bool _builderLinked = false;
  bool _printerLinked = false;

  CustomLogger() {
    assert(this is L);
    registerLevels();
  }

  @protected
  CustomLogger.sub(L parent) {
    assert(this is L);
    registerLevels();

    parent.registerSublogger(this as L);

    level = parent.level;
    for (final parentLevelLogger in parent._levelLoggers.values) {
      final levelLogger = _levelLoggers[parentLevelLogger.level];
      if (levelLogger != null) {
        builder = parentLevelLogger.builder;
        printer = parentLevelLogger.printer;
      }
    }

    _levelLinked = true;
    _builderLinked = true;
    _printerLinked = true;
  }

  @visibleForTesting
  int get subLoggersCount => _subloggers.length;

  bool get levelLinked => _levelLinked;
  bool get builderLinked => _builderLinked;
  bool get printerLinked => _printerLinked;

  LL operator [](int level) =>
      _levelLoggers[level] ??
      (throw StateError('Level $level is not registered'));

  @protected
  void registerLevels();

  @protected
  void registerLevel(LL levelLogger) {
    if (_levelLoggers.containsKey(levelLogger.level)) {
      throw StateError('Level ${levelLogger.level} is already registered');
    }
    _levelLoggers[levelLogger.level] = levelLogger;
    levelLogger._attach(this as L);
  }

  int get level => _level;
  set level(int value) {
    _level = value;
    _levelLinked = false;

    for (final levelLogger in _levelLoggers.values) {
      levelLogger._toggle(value <= levelLogger.level);
    }

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger? when sublogger._levelLinked) {
        final tmp = sublogger._levelLinked;
        sublogger
          ..level = value
          .._levelLinked = tmp;
      }
    }
  }

  bool isLoggable(int level) => _level <= level;

  /// Sets the log message builder.
  ///
  /// ```dart
  /// log.builder = (entry) {
  ///   return '${entry.levelName.toUpperCase()}: ${entry.message}';
  /// };
  /// ```
  // ignore: avoid_setters_without_getters
  set builder(CustomLogBuilder<Ent, Out> value) {
    _builderLinked = false;

    for (final logger in _levelLoggers.values) {
      logger._builder = value;
    }

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._builderLinked) {
        sublogger
          ..builder = value
          .._builderLinked = true;
      }
    }
  }

  /// Sets the log message builder for a specific level.
  ///
  /// ```dart
  /// log.setBuilderForLevel(Levels.info, (entry) {
  ///   return '${entry.levelName.toUpperCase()}: ${entry.message}';
  /// });
  /// ```
  void _setLevelBuilder(int level, CustomLogBuilder<Ent, Out> value) {
    _builderLinked = false;
    this[level]._builder = value;

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._builderLinked) {
        sublogger
          .._setLevelBuilder(level, value)
          .._builderLinked = true;
      }
    }
  }

  /// Sets the log printer.
  ///
  /// ```dart
  /// // Use `print`.
  /// log.printer = print;
  ///
  /// // Use a custom log printer.
  /// log.printer = stderr.writeln;
  /// ```
  // ignore: avoid_setters_without_getters
  set printer(CustomLogPrinter<Out> printer) {
    _printerLinked = false;

    for (final logger in _levelLoggers.values) {
      logger._printer = printer;
    }

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._printerLinked) {
        sublogger
          ..printer = printer
          .._printerLinked = true;
      }
    }
  }

  /// Sets the log printer for a specific level.
  ///
  /// ```dart
  /// log.setPrinterForLevel(Levels.info, stdout.writeln);
  /// ```
  void _setLevelPrinter(int level, CustomLogPrinter<Out> printer) {
    _printerLinked = false;
    this[level]._printer = printer;

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._printerLinked) {
        sublogger
          .._setLevelPrinter(level, printer)
          .._printerLinked = true;
      }
    }
  }

  @protected
  void registerSublogger(L sublogger) {
    _subloggers.add(WeakReference(sublogger));
    _finalizer.attach(sublogger, this);
  }
}
