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
  // Strong on purpose, while the list above is weak. A sublogger keeps its
  // ancestors alive, so a live leaf never loses the chain it inherits from;
  // an abandoned branch is still collected whole, because nothing points
  // down into it.
  Logger? _parent;
  bool _levelLinked = false;
  bool _publisherLinked = false;
  // The last publisher assigned through `publisher =`, kept so that levels
  // registered later do not silently stay on the no-op publisher.
  CustomLogPublisher<Log>? _defaultPublisher;
  LogTransformer<Log>? _transformer;
  bool _transformerLinked = false;
  bool _transforming = false;
  void Function(Object error, StackTrace stackTrace)? _onError;
  int _prunedAt = 0;

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
  /// This sublogger initially inherits the [level], the applicable publishers
  /// and the [transformer] from the [parent]. Updates to all three propagate
  /// to this sublogger, unless overridden manually on this instance.
  @protected
  CustomLogger.sub(Logger parent) {
    assert(this is Logger);
    registerLevels();

    _parent = parent;
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
  void pruneSubloggers() {
    _subloggers.removeWhere((sublogger) => sublogger.target == null);
    _prunedAt = _subloggers.length;
  }

  /// Prunes only once the list has doubled since the last prune.
  ///
  /// Registration must not scan the whole list every time: creating n
  /// subloggers under one parent would then cost O(n²), and creating
  /// a sublogger per request or per widget is the documented pattern.
  /// Traversals still prune unconditionally — they are O(n) anyway.
  void _pruneSubloggersIfGrown() {
    if (_subloggers.length >= (_prunedAt < 16 ? 16 : _prunedAt * 2)) {
      pruneSubloggers();
    }
  }

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
  /// current [level], per-level publishers and [transformer], and turns
  /// propagation of future parent updates back on.
  ///
  /// A sublogger detaches implicitly when its [level], [publisher] or
  /// [transformer] is assigned directly (`child.level = child.level` and
  /// `child.transformer = child.transformer` are the idioms to unlink
  /// without changing the value; for publishers, assign
  /// `child[level].publisher = child[level].publisher`); this method is the
  /// reverse operation.
  ///
  /// Levels this logger registered but the parent did not are given the
  /// parent's common publisher, if it ever assigned one; the parent's
  /// per-level publishers are then applied on top.
  ///
  /// Returns `false` only when this logger has no parent, i.e. it is a root
  /// logger. A sublogger holds its parent strongly, so the link can never be
  /// lost to garbage collection.
  bool relink() => _relink();

  bool _relink() {
    final parent = _parent;
    if (parent == null) {
      return false;
    }

    // Private setters throughout: the public ones are overridable, and this
    // runs from the `sub` constructor, before a subclass body has executed.
    _setLevel(parent.level);
    _setTransformer(parent._transformer);
    // Levels this logger has and the parent does not would otherwise keep
    // whatever publisher they were left with.
    if (parent._defaultPublisher case final publisher?) {
      _setPublisher(publisher);
    }
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
  /// Throws a [StateError] if this level value is already registered, or if
  /// [levelLogger] already belongs to another logger — sharing one level
  /// logger between loggers would silently hand this logger's logs to the
  /// other one's publisher and transformer.
  ///
  /// A level registered after [publisher] was assigned inherits that
  /// publisher; otherwise it would look enabled and publish into the no-op
  /// publisher.
  @protected
  void registerLevel(LevelLogger levelLogger) {
    if (_levelLoggers.containsKey(levelLogger.level)) {
      throw StateError('Level ${levelLogger.level} is already registered');
    }
    _levelLoggers[levelLogger.level] = levelLogger;
    levelLogger._attach(this as Logger);
    if (_defaultPublisher case final publisher?) {
      levelLogger._publisher = publisher;
    }
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
  set level(int value) => _setLevel(value);

  void _setLevel(int value) {
    _level = value;
    _levelLinked = false;

    for (final levelLogger in _levelLoggers.values) {
      levelLogger._toggle(value <= levelLogger.level);
    }

    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger? when sublogger._levelLinked) {
        sublogger
          .._setLevel(value)
          .._levelLinked = true;
      }
    }
  }

  /// Returns `true` if the specified [level] meets the logging threshold.
  bool isLoggable(int level) => _level <= level;

  /// Assigns a common [CustomLogPublisher] to all registered log levels.
  ///
  /// This overwrites any per-level publisher set earlier through
  /// `logger[level].publisher`, so assign the common publisher first and the
  /// per-level exceptions after it.
  ///
  /// Propagates the publisher change to linked subloggers. Detaches this
  /// logger's publisher link if it is a sublogger (use [relink] to
  /// re-attach).
  // ignore: avoid_setters_without_getters
  set publisher(CustomLogPublisher<Log> publisher) => _setPublisher(publisher);

  void _setPublisher(CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;
    _defaultPublisher = publisher;

    for (final logger in _levelLoggers.values) {
      logger._publisher = publisher;
    }

    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          .._setPublisher(publisher)
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
  /// the error goes to [onError], or to the current zone via
  /// [Zone.handleUncaughtError] when no handler is set. `TransformPublisher`
  /// has its own `onError` for the per-destination case.
  ///
  /// > [!WARNING]
  /// > A transformer must not log through its own logger, and neither must
  /// > a publisher: the nested call comes straight back and recurses until
  /// > the stack is exhausted. Both cycles are detected — the nested log is
  /// > dropped and a [StateError] goes to [onError] or the current zone.
  /// > Treat that as a guard against runaway recursion, not as a supported
  /// > way to log from a transformer or a publisher.
  /// >
  /// > The guard is **synchronous**, and that word carries all three of its
  /// > limits. The transformer half is per logger: it catches any cycle that
  /// > returns to this logger while its transformer is still running, across
  /// > several levels or several loggers. The publisher half is per level
  /// > logger, so a publisher that logs at a *different* level of the same
  /// > logger is allowed — a cycle still trips the guard the moment it comes
  /// > back to a level whose publisher is running.
  /// >
  /// > Three things it does **not** catch. A cycle through a sublogger that
  /// > inherited the same transformer: a sublogger is a separate logger with
  /// > its own guard, so the nested log is transformed again and published.
  /// > A deferred nested log — `scheduleMicrotask`, a `Future`, an `await` —
  /// > runs after the guard has been released, so an unconditional one loops
  /// > forever. And, for the same reason, **an asynchronous publisher**: its
  /// > `handle` runs long after `publish` returned, so a handler that logs
  /// > into its own logger is not guarded at all and will grow the queue
  /// > without bound instead of overflowing the stack. Logging into an
  /// > unrelated logger is untouched.
  LogTransformer<Log>? get transformer => _transformer;

  /// Sets the log [transformer].
  ///
  /// Propagates the change to linked subloggers. Detaches this logger's
  /// transformer link if it is a sublogger
  /// (`child.transformer = child.transformer` unlinks without changing the
  /// value; use [relink] to re-attach).
  set transformer(LogTransformer<Log>? value) => _setTransformer(value);

  void _setTransformer(LogTransformer<Log>? value) {
    _transformer = value;
    _transformerLinked = false;

    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._transformerLinked) {
        sublogger
          .._setTransformer(value)
          .._transformerLinked = true;
      }
    }
  }

  /// Called for every error this logger catches on the publish path: a
  /// throwing [transformer], a throwing publisher, and a reentrancy guard
  /// violation.
  ///
  /// When `null` (the default) each case keeps its historical behaviour: the
  /// transformer error and the guard violation are reported to the current
  /// zone via [Zone.handleUncaughtError], and a publisher error propagates
  /// out of the logging call. Note what the zone route means in a plain Dart
  /// program without an error zone: an uncaught asynchronous error terminates
  /// the isolate by default, so a bug in a masking [transformer] takes the
  /// process down. Setting this callback is how logging stops being able to
  /// break the application that logs.
  ///
  /// Unlike [level], the publishers and [transformer], this is resolved
  /// dynamically through the parent chain rather than copied down: a
  /// sublogger with no handler of its own uses its parent's. There is no link
  /// flag and [relink] does not affect it — assigning `null` restores the
  /// inherited handler instead of detaching.
  ///
  /// A throwing handler cannot wedge logging: its own error goes to the
  /// current zone.
  void Function(Object error, StackTrace stackTrace)? get onError =>
      _onError ?? _parent?.onError;

  set onError(void Function(Object error, StackTrace stackTrace)? value) =>
      _onError = value;

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
    _pruneSubloggersIfGrown();
    _subloggers.add(WeakReference(sublogger));
  }
}
