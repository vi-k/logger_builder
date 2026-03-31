import 'package:meta/meta.dart';

import '../utils/levels.dart';
import 'custom_log.dart';
import 'custom_log_publisher.dart';

part 'custom_level_logger.dart';

/// An abstract base class for creating customized loggers.
///
/// This class serves as the core of a flexible logging system, supporting
/// hierarchical subloggers, dynamically configurable levels, and customizable
/// message builders and printers.
///
/// It uses four generic type parameters to ensure type safety across the
/// system:
/// - [Logger]: The concrete implementation class of the logger extending
///   [CustomLogger].
/// - [LevelLogger]: The concrete implementation class of [CustomLevelLogger]
///   used by [Logger].
/// - [LogFn]: The function signature used for emitting logs for specific
///   levels.
/// - [Log]: The concrete type of [CustomLog] used by a log publisher.
///
/// Subclasses must implement the [registerLevels] method to configure their
/// associated [CustomLevelLogger]s.
abstract base class CustomLogger<
    Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log>,
    LevelLogger extends CustomLevelLogger<Logger, LevelLogger, LogFn, Log>,
    LogFn extends Function,
    Log extends CustomLog> {
  static final Finalizer<CustomLogger> _finalizer = Finalizer((logger) {
    logger._subloggers.removeWhere((subLogger) => subLogger.target == null);
  });

  int _level = Levels.off;
  final Map<int, LevelLogger> _levelLoggers = {};
  final List<WeakReference<Logger>> _subloggers = [];
  bool _levelLinked = false;
  bool _publisherLinked = false;

  /// Creates a new [CustomLogger] instance and registers its levels.
  ///
  /// The [registerLevels] method is invoked synchronously during
  /// initialization.
  CustomLogger() {
    assert(this is Logger);
    registerLevels();
  }

  /// Creates a sublogger linked to a [parent] logger.
  ///
  /// This sublogger initially inherits the [level] and applicable publishers
  /// from the [parent]. Updates to the parent's level and publisher will
  /// propagate to this sublogger, unless overridden manually on this instance.
  @protected
  CustomLogger.sub(Logger parent) {
    assert(this is Logger);
    registerLevels();

    parent.registerSublogger(this as Logger);

    level = parent.level;
    for (final parentLevelLogger in parent._levelLoggers.values) {
      final levelLogger = _levelLoggers[parentLevelLogger.level];
      if (levelLogger != null) {
        levelLogger.publisher = parentLevelLogger.publisher;
      }
    }

    _levelLinked = true;
    _publisherLinked = true;
  }

  /// Returns the number of directly attached subloggers.
  @visibleForTesting
  int get subLoggersCount => _subloggers.length;

  /// Returns `true` if this logger's level is synchronized with its parent.
  @visibleForTesting
  bool get levelLinked => _levelLinked;

  /// Returns `true` if this logger's publisher is synchronized with its
  /// parent.
  @visibleForTesting
  bool get publisherLinked => _publisherLinked;

  /// Retrieves the [LevelLogger] associated with the given numerical [level].
  ///
  /// Throws a [StateError] if the exact [level] is not registered.
  LevelLogger operator [](int level) =>
      _levelLoggers[level] ??
      (throw StateError('Level $level is not registered'));

  /// Registers all the log levels supported by this logger.
  ///
  /// Implementations must use the [registerLevel] method within this method
  /// to add their predefined [CustomLevelLogger]s.
  @protected
  void registerLevels();

  /// Registers a specific [levelLogger] dynamically.
  ///
  /// Throws a [StateError] if this level value is already registered.
  @protected
  void registerLevel(LevelLogger levelLogger) {
    if (_levelLoggers.containsKey(levelLogger.level)) {
      throw StateError('Level ${levelLogger.level} is already registered');
    }
    _levelLoggers[levelLogger.level] = levelLogger;
    levelLogger._attach(this as Logger);
  }

  /// The overall log level threshold of this logger.
  int get level => _level;

  /// Sets the log [level] threshold.
  ///
  /// Enables all level loggers with a level equal to or exceeding [value],
  /// and disables the others. Propagates the level change down to linked
  /// subloggers. Detaches this logger's level link if it is a sublogger.
  set level(int value) {
    _level = value;
    _levelLinked = false;

    for (final levelLogger in _levelLoggers.values) {
      levelLogger._toggle(value <= levelLogger.level);
    }

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger? when sublogger._levelLinked) {
        sublogger
          ..level = value
          .._levelLinked = true;
      }
    }
  }

  /// Returns `true` if the specified [level] meets the logging threshold.
  bool isLoggable(int level) => _level <= level;

  /// Assigns a common [CustomLogPublisher] to all registered log levels.
  ///
  /// Propagates the publisher change to linked subloggers.
  // ignore: avoid_setters_without_getters
  set publisher(CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;

    for (final logger in _levelLoggers.values) {
      logger._publisher = publisher;
    }

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          ..publisher = publisher
          .._publisherLinked = true;
      }
    }
  }

  void _setLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;
    this[level]._publisher = publisher;

    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          .._setLevelPublisher(level, publisher)
          .._publisherLinked = true;
      }
    }
  }

  /// Subscribes a [sublogger] to level and publisher updates dynamically.
  ///
  /// Subloggers are held using weak references to prevent memory leaks if
  /// they are discarded elsewhere in the application.
  @protected
  void registerSublogger(Logger sublogger) {
    _subloggers.add(WeakReference(sublogger));
    _finalizer.attach(sublogger, this);
  }
}
