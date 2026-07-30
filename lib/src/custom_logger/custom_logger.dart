import 'dart:async';

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
  int _level = Levels.off;
  final Map<int, LevelLogger> _levelLoggers = {};
  final List<WeakReference<Logger>> _subloggers = [];
  WeakReference<Logger>? _parent;
  bool _levelLinked = false;
  bool _publisherLinked = false;
  LogTransformer<Log>? _transformer;
  bool _transformerLinked = false;

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

    _parent = WeakReference(parent);
    parent.registerSublogger(this as Logger);
    // The private counterpart of [relink]: a virtual call here would reach
    // subclass overrides before their constructor bodies have run.
    _relink();
  }

  /// Returns the number of directly attached subloggers.
  ///
  /// For tests only; not intended for production use.
  @visibleForTesting
  int get subLoggersCount => _subloggers.length;

  /// Removes references to subloggers that have already been garbage
  /// collected.
  ///
  /// Called automatically before every traversal of the subloggers, so the
  /// internal list does not grow unboundedly. Exposed for deterministic
  /// tests.
  @visibleForTesting
  void pruneSubloggers() =>
      _subloggers.removeWhere((sublogger) => sublogger.target == null);

  /// Returns `true` if this logger's level is synchronized with its parent.
  ///
  /// For tests only; not intended for production use.
  @visibleForTesting
  bool get levelLinked => _levelLinked;

  /// Returns `true` if this logger's publisher is synchronized with its
  /// parent.
  ///
  /// For tests only; not intended for production use.
  @visibleForTesting
  bool get publisherLinked => _publisherLinked;

  /// Returns `true` if this logger's transformer is synchronized with its
  /// parent.
  ///
  /// For tests only; not intended for production use.
  @visibleForTesting
  bool get transformerLinked => _transformerLinked;

  /// Retrieves the [LevelLogger] associated with the given numerical [level].
  ///
  /// Throws a [StateError] if the exact [level] is not registered.
  LevelLogger operator [](int level) =>
      _levelLoggers[level] ??
      (throw StateError('Level $level is not registered'));

  /// The numeric values of the registered levels.
  ///
  /// A live view in registration order, not a snapshot.
  Iterable<int> get levels => _levelLoggers.keys;

  /// Re-attaches this sublogger to its parent: re-inherits the parent's
  /// current [level] and per-level publishers, and turns propagation of
  /// future parent updates back on.
  ///
  /// A sublogger detaches implicitly when its [level] or [publisher] is
  /// assigned directly (`child.level = child.level` is the idiom to unlink
  /// without changing the value); this method is the reverse operation.
  ///
  /// Returns `false` when this logger has no parent (a root logger) or the
  /// parent has already been garbage collected.
  bool relink() => _relink();

  bool _relink() {
    final parent = _parent?.target;
    if (parent == null) {
      return false;
    }

    level = parent.level;
    transformer = parent._transformer;
    for (final parentLevelLogger in parent._levelLoggers.values) {
      _inheritLevelPublisher(
        parentLevelLogger.level,
        parentLevelLogger._publisher,
      );
    }

    _levelLinked = true;
    _publisherLinked = true;
    _transformerLinked = true;
    return true;
  }

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
  /// subloggers. Detaches this logger's level link if it is a sublogger
  /// (`child.level = child.level` unlinks without changing the value;
  /// use [relink] to re-attach).
  set level(int value) {
    _level = value;
    _levelLinked = false;

    for (final levelLogger in _levelLoggers.values) {
      levelLogger._toggle(value <= levelLogger.level);
    }

    pruneSubloggers();
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
  /// Propagates the publisher change to linked subloggers. Detaches this
  /// logger's publisher link if it is a sublogger (use [relink] to
  /// re-attach).
  // ignore: avoid_setters_without_getters
  set publisher(CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;

    for (final logger in _levelLoggers.values) {
      logger._publisher = publisher;
    }

    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          ..publisher = publisher
          .._publisherLinked = true;
      }
    }
  }

  /// The transformer applied to every log of this logger right before it
  /// is handed to the publisher (see [CustomLevelLogger.publishLog]).
  ///
  /// Intended primarily for security: masking secrets and PII, or dropping
  /// forbidden logs entirely (`null` return). `null` (the default) means
  /// no transformation.
  ///
  /// Fail-closed: if the transformer throws, the log is NOT published and
  /// the error is reported to the current zone via
  /// [Zone.handleUncaughtError]. Use `TransformPublisher` with its
  /// `onError` for a custom error callback.
  LogTransformer<Log>? get transformer => _transformer;

  /// Sets the log [transformer].
  ///
  /// Propagates the change to linked subloggers. Detaches this logger's
  /// transformer link if it is a sublogger
  /// (`child.transformer = child.transformer` unlinks without changing the
  /// value; use [relink] to re-attach).
  set transformer(LogTransformer<Log>? value) {
    _transformer = value;
    _transformerLinked = false;

    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._transformerLinked) {
        sublogger
          ..transformer = value
          .._transformerLinked = true;
      }
    }
  }

  void _setLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;
    this[level]._publisher = publisher;
    _propagateLevelPublisher(level, publisher);
  }

  /// Same as [_setLevelPublisher], but silently skips this logger when it
  /// did not register [level]: a sublogger is not required to have all the
  /// levels of its parent.
  void _inheritLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;
    _levelLoggers[level]?._publisher = publisher;
    _propagateLevelPublisher(level, publisher);
  }

  void _propagateLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          .._inheritLevelPublisher(level, publisher)
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
    pruneSubloggers();
    _subloggers.add(WeakReference(sublogger));
  }
}
