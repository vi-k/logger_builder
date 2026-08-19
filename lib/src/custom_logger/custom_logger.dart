import 'dart:async';

import 'package:meta/meta.dart';

import '../utils/levels.dart';
import 'custom_log.dart';
import 'custom_log_publisher.dart';

part 'custom_level_logger.dart';

/// An abstract base class for creating customized loggers.
///
/// This class serves as the core of a flexible logging system, supporting
/// hierarchical subloggers, dynamically configurable levels, and pluggable
/// output: each level carries a [CustomLogPublisher], and a [transformer] can
/// rewrite or drop a log on its way there.
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
  /// Called automatically before every traversal of the subloggers, and
  /// amortized on registration, so the internal list does not grow
  /// unboundedly on its own. Call it directly to compact immediately after
  /// dropping a large subtree, or in a test that needs a deterministic
  /// moment.
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
  /// Supported API, not a test hook: with [relink] public, "is this sublogger
  /// still following its parent?" is a question production code may need to
  /// answer.
  bool get levelLinked => _levelLinked;

  /// Returns `true` if this logger's publisher is synchronized with its
  /// parent.
  ///
  /// Supported API, not a test hook: with [relink] public, "is this sublogger
  /// still following its parent?" is a question production code may need to
  /// answer.
  ///
  /// Only the common [publisher] setter drops this link. Pinning a single
  /// level through `logger[level].publisher` leaves it up — that question
  /// belongs to the level: [CustomLevelLogger.hasOwnPublisher].
  bool get publisherLinked => _publisherLinked;

  /// Returns `true` if this logger's transformer is synchronized with its
  /// parent.
  ///
  /// Supported API, not a test hook: with [relink] public, "is this sublogger
  /// still following its parent?" is a question production code may need to
  /// answer.
  bool get transformerLinked => _transformerLinked;

  /// Retrieves the [LevelLogger] associated with the given numerical [level].
  ///
  /// Throws a [StateError] if the exact [level] is not registered.
  LevelLogger operator [](int level) =>
      _levelLoggers[level] ??
      (throw StateError('Level $level is not registered'));

  /// The numeric values of the registered levels, in registration order.
  ///
  /// A snapshot, not a live view: registering a level while iterating this
  /// used to throw [ConcurrentModificationError]. The set is normally built
  /// once, so the copy costs nothing worth keeping the hazard for.
  List<int> get levels => List<int>.unmodifiable(_levelLoggers.keys);

  /// Re-attaches this sublogger to its parent: re-inherits the parent's
  /// current [level], per-level publishers and [transformer], and turns
  /// propagation of future parent updates back on.
  ///
  /// A sublogger detaches implicitly when its [level], [publisher] or
  /// [transformer] is assigned directly (`child.level = child.level` and
  /// `child.transformer = child.transformer` are the idioms to unlink
  /// without changing the value); this method is the reverse operation,
  /// and it also drops every per-level pin. To put a single level back
  /// under the chain, use [CustomLevelLogger.relink].
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

    // A full relink drops every pin: the logger goes back to following
    // its parent in whole, levels included.
    for (final levelLogger in _levelLoggers.values) {
      levelLogger._hasOwnPublisher = false;
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
      // Only real publishers: copying the parent's no-op default down would
      // make this logger's level report `hasPublisher` for a publisher that
      // goes nowhere, which is exactly the state that getter exists to
      // expose.
      if (parentLevelLogger.hasPublisher) {
        _inheritLevelPublisher(
          parentLevelLogger.level,
          parentLevelLogger._publisher,
        );
      }
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
  /// The new level inherits a publisher rather than starting on the no-op
  /// one, which would look enabled and publish into nothing. What it
  /// inherits, in order: the parent's publisher for exactly this level if
  /// this logger still follows its parent, then the last common publisher
  /// assigned anywhere up the chain.
  ///
  /// If neither exists — a logger configured only through
  /// `logger[level].publisher`, for instance — the level stays on the no-op
  /// publisher. Handing it the publisher chosen for some *other* level would
  /// be an invention, so it is left unconfigured and made visible instead:
  /// [CustomLevelLogger.hasPublisher] is `false` while [isLoggable] and
  /// `isEnabled` are `true`.
  @protected
  void registerLevel(LevelLogger levelLogger) {
    if (_levelLoggers.containsKey(levelLogger.level)) {
      throw StateError('Level ${levelLogger.level} is already registered');
    }
    _levelLoggers[levelLogger.level] = levelLogger;
    levelLogger._attach(this as Logger);
    if (_publisherFor(levelLogger.level) case final publisher?) {
      levelLogger._setPublisher(publisher);
    }
  }

  /// The publisher a level newly registered at [level] should start on.
  ///
  /// A single rule instead of a cached field: `_defaultPublisher` is written
  /// only by the common `publisher =` setter, so a logger configured entirely
  /// through `logger[level].publisher` had nothing cached and left later
  /// levels on the no-op publisher — enabled, reporting `isEnabled == true`,
  /// publishing into nothing.
  CustomLogPublisher<Log>? _publisherFor(int level) {
    final parent = _parent;
    if (_publisherLinked && parent != null) {
      final inherited =
          parent._assignedPublisherFor(level) ?? parent._publisherFor(level);
      if (inherited != null) {
        return inherited;
      }
    }

    return _defaultPublisher;
  }

  /// This logger's own publisher for [level], but only if one was really
  /// assigned — the no-op default is not worth inheriting.
  CustomLogPublisher<Log>? _assignedPublisherFor(int level) {
    if (_levelLoggers[level] case final levelLogger?
        when levelLogger.hasPublisher) {
      return levelLogger._publisher;
    }

    return null;
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

  // Load-bearing ordering, in this method and in the three propagation
  // methods below: the `*Linked` flag is cleared *before* recursing and
  // restored *after*, so while a subtree is being walked its own flag is
  // down. That doubles as an in-progress marker and is the only thing that
  // stops a cycle in the sublogger graph — `registerSublogger` is protected,
  // so a subclass can build `root -> a -> b -> a` — from recursing until the
  // stack is exhausted. Hoisting the assignment to the end of the method
  // would reintroduce that crash, which is why it is spelled out here.
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
  ///
  /// [Levels.all] and [Levels.off] are thresholds, not levels, and no level
  /// logger can be registered on either (the [CustomLevelLogger] constructor
  /// rejects them), so both answer `false`. Without that guard
  /// `isLoggable(Levels.off)` was `true` for a logger set to
  /// `Levels.off` — a predicate contradicting "logging is completely
  /// disabled" for any code that guards on it.
  bool isLoggable(int level) =>
      level > Levels.all && level < Levels.off && _level <= level;

  /// Assigns a common [CustomLogPublisher] to every registered log level
  /// that does not hold a publisher of its own.
  ///
  /// A level pinned through `logger[level].publisher` keeps what it was
  /// given: its own logger does not overrule it either, so the order of
  /// the two assignments no longer matters.
  /// [CustomLevelLogger.relink] puts a pinned level back under this
  /// setter.
  ///
  /// Propagates the publisher change to linked subloggers. Detaches this
  /// logger's publisher link if it is a sublogger (use [relink] to
  /// re-attach).
  // ignore: avoid_setters_without_getters
  set publisher(CustomLogPublisher<Log> publisher) => _setPublisher(publisher);

  // The flag is cleared before recursing and restored after, which also
  // breaks cycles in the sublogger graph — see the note on [_setLevel].
  void _setPublisher(CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;
    _defaultPublisher = publisher;

    for (final levelLogger in _levelLoggers.values) {
      // A pinned level holds its own publisher; its own logger does not
      // overrule it either, so the order of the two assignments stops
      // mattering.
      if (!levelLogger._hasOwnPublisher) {
        levelLogger._setPublisher(publisher);
      }
    }

    _propagatePublisher(publisher);
  }

  /// The common publisher of [parent], arriving from above.
  ///
  /// Not [_setPublisher]: a level here follows the parent's value *for
  /// that level*, which is [publisher] only where the parent holds no pin
  /// of its own. Handing [publisher] to every level would overwrite what a
  /// pinned level of the parent still publishes into.
  void _inheritPublisher(Logger parent, CustomLogPublisher<Log> publisher) {
    _defaultPublisher = publisher;

    for (final levelLogger in _levelLoggers.values) {
      if (levelLogger._hasOwnPublisher) {
        continue;
      }
      levelLogger._setPublisher(
        parent._assignedPublisherFor(levelLogger.level) ?? publisher,
      );
    }

    _propagatePublisher(publisher);
  }

  void _propagatePublisher(CustomLogPublisher<Log> publisher) {
    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          .._publisherLinked = false
          .._inheritPublisher(this as Logger, publisher)
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

  // The flag is cleared before recursing and restored after, which also
  // breaks cycles in the sublogger graph — see the note on [_setLevel].
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
  ///
  /// Wrap an arrow function in parentheses when assigning it inside
  /// a cascade, as with [transformer] — without them the `..` of the next
  /// section is parsed as part of the arrow's body, and the error points at
  /// the following line rather than at this one:
  ///
  /// ```dart
  /// final log = Logger()
  ///   ..level = Levels.all
  ///   ..onError = ((error, stackTrace) => report(error, stackTrace))
  ///   ..publisher = const DefaultLogPublisher();
  /// ```
  void Function(Object error, StackTrace stackTrace)? get onError =>
      _onError ?? _parent?.onError;

  set onError(void Function(Object error, StackTrace stackTrace)? value) =>
      _onError = value;

  // A direct per-level assignment pins the level and leaves this logger's
  // link to its parent alone: pinning one level must not stop the others
  // from following the parent.
  void _setLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    this[level]
      .._setPublisher(publisher)
      .._hasOwnPublisher = true;
    _propagateLevelPublisher(level, publisher);
  }

  /// Same as [_setLevelPublisher], but arriving from the parent: the level
  /// takes the value without pinning, and this logger is silently skipped
  /// when it did not register [level] — a sublogger is not required to
  /// have all the levels of its parent.
  ///
  /// A `null` [publisher] is the "there is nothing above this level any
  /// more" case of [_relinkLevel]: an unpinned level goes back to the
  /// no-op publisher instead of keeping the value it used to inherit.
  /// Leaving it in place would break the rule that an unpinned level
  /// always equals what the chain gives; handing the no-op publisher down
  /// as a value would leave [CustomLevelLogger.hasPublisher] `true` on a
  /// level that publishes nowhere.
  ///
  /// A pinned level stops the descent here: it does not change, so nothing
  /// below it inherits a change either.
  void _inheritLevelPublisher(int level, CustomLogPublisher<Log>? publisher) {
    if (_levelLoggers[level] case final levelLogger?) {
      if (levelLogger._hasOwnPublisher) {
        return;
      }
      if (publisher != null) {
        levelLogger._setPublisher(publisher);
      } else {
        levelLogger._resetPublisher();
      }
    }
    _propagateLevelPublisher(level, publisher);
  }

  // The link flag is cleared before recursing and restored after, which
  // also breaks cycles in the sublogger graph — see the note on
  // [_setLevel]. It stays the marker on this path too: the pin cannot
  // serve, because a logger that did not register [level] has no pin to
  // raise and a cycle through it would recurse until the stack is gone.
  void _propagateLevelPublisher(
    int level,
    CustomLogPublisher<Log>? publisher,
  ) {
    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          .._publisherLinked = false
          .._inheritLevelPublisher(level, publisher)
          .._publisherLinked = true;
      }
    }
  }

  void _relinkLevel(int level) {
    final levelLogger = this[level];
    if (!levelLogger._hasOwnPublisher) {
      return;
    }

    levelLogger._hasOwnPublisher = false;
    final inherited = _publisherFor(level);
    if (inherited != null) {
      levelLogger._setPublisher(inherited);
    } else {
      levelLogger._resetPublisher();
    }

    // The chain's answer, not `levelLogger._publisher`: with nothing above,
    // the second is the no-op publisher, and handing that down as a value
    // would leave every linked sublogger reporting `hasPublisher == true`
    // for a level that publishes nowhere. `null` propagates the reset.
    _propagateLevelPublisher(level, inherited);
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
