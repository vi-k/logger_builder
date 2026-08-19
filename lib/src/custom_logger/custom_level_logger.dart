part of 'custom_logger.dart';

/// An abstract base class representing a specific log level for
/// a [CustomLogger].
///
/// Instances of this class handle logging operations for a particular log
/// level. A subclass builds a [CustomLog] in [processLog] and hands it to
/// [publishLog], which applies the logger's [CustomLogger.transformer] and
/// then the level's [CustomLogPublisher].
///
/// When the logger's level is above this level logger's configured [level],
/// calls to the actual logic will be replaced with a no-op function to avoid
/// unnecessary computations.
///
/// It takes the same generic type parameters as [CustomLogger].
abstract base class CustomLevelLogger<
    Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log>,
    LevelLogger extends CustomLevelLogger<Logger, LevelLogger, LogFn, Log>,
    LogFn extends Function,
    Log extends CustomLog> {
  /// Numerical value of the level of this [LevelLogger] logger.
  ///
  /// Must be greater than [Levels.all] (0) and less than [Levels.off]
  /// (2000) — checked in the constructor. Those two are thresholds, not
  /// levels: a level logger registered at [Levels.off] would still be
  /// enabled with `logger.level = Levels.off`.
  ///
  /// See some examples here: [Levels].
  final int level;

  /// Name of the level of this [LevelLogger] logger.
  final String name;

  /// Short name of the level of this [LevelLogger] logger.
  ///
  /// Default is equal to the first letter of the name.
  final String shortName;

  /// Plug function when logging is disabled for this level.
  ///
  /// Stored once and compared by identity in [isEnabled], so any function
  /// works — static, global or a closure created inline in the constructor
  /// call. A static or global one merely avoids allocating a closure per
  /// level logger.
  final LogFn _noLog;

  /// Link to [CustomLogger] logger.
  ///
  /// The [CustomLevelLogger] logger is attached to [CustomLogger] logger using
  /// the [CustomLogger.registerLevel] method.
  Logger? _logger;

  /// Current log function.
  ///
  /// If logging is enabled for this level, it is equal to [processLog].
  /// Otherwise, it is equal to [_noLog].
  LogFn _log;

  /// Current publisher.
  CustomLogPublisher<Log> _publisher;

  /// Whether [_publisher] is a real publisher rather than the no-op default.
  ///
  /// Kept as a flag because the no-op publisher is private and generic, so
  /// there is no supported way to recognise it from the outside — which used
  /// to make an enabled-but-unconfigured level indistinguishable from a
  /// working one.
  bool _hasPublisher;

  /// Whether this level holds a publisher of its own.
  ///
  /// Set by `logger[level].publisher = ...` and cleared by [relink] on
  /// this level, or by [CustomLogger.relink] on the whole logger, which
  /// drops every other level's pin along with it. A level that holds its
  /// own publisher takes nothing from above: neither a parent update nor
  /// its own logger's common `publisher` setter overrules it, so the
  /// order of the two assignments stops mattering.
  ///
  /// Different question from [hasPublisher], which asks whether the
  /// publisher is a real one rather than the no-op default: an inherited
  /// publisher is real but not its own.
  bool _hasOwnPublisher = false;

  /// Reentrancy guard for the publish step, held per level logger.
  ///
  /// Per level logger, not per logger: a cycle always comes back to *some*
  /// level logger, so this still catches every runaway recursion — including
  /// one that travels through several levels or several loggers — while a
  /// provably terminating pattern (an error publisher noting what it did at
  /// info level, through a publisher that logs nothing) is no longer
  /// rejected.
  bool _publishing = false;

  /// Creates a level logger.
  ///
  /// The [level] must lie strictly between [Levels.all] and [Levels.off],
  /// and the [name] must not be empty; otherwise an [ArgumentError] is
  /// thrown. When [shortName] is omitted, the first character (code point)
  /// of [name] is used.
  CustomLevelLogger({
    required int level,
    required String name,
    String? shortName,
    required LogFn noLog,
    CustomLogPublisher<Log>? publisher,
  })  : level = _checkLevel(level),
        name = _checkName(name),
        shortName = shortName ?? _firstCharacter(name),
        _noLog = noLog,
        _log = noLog,
        _publisher = publisher ?? const CustomLogPublisher.noOp(),
        _hasPublisher = publisher != null;

  static int _checkLevel(int level) {
    // Checked in every build mode, like the name: Levels.all and Levels.off
    // are thresholds, not levels, and a level logger sitting on one of them
    // silently defeats `logger.level = Levels.off`.
    if (level <= Levels.all || level >= Levels.off) {
      throw ArgumentError.value(
        level,
        'level',
        'must be greater than Levels.all (${Levels.all}) and less than '
            'Levels.off (${Levels.off})',
      );
    }

    return level;
  }

  static String _checkName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }

    return name;
  }

  static String _firstCharacter(String name) =>
      String.fromCharCodes(name.runes.take(1));

  /// Generates or executes the actual logging procedure when this level is
  /// active.
  ///
  /// Subclasses should implement this property to return the appropriate
  /// [LogFn].
  @protected
  LogFn get processLog;

  /// Returns the current logging function based on the active state.
  ///
  /// If [isEnabled] is `true`, it delegates to [processLog]. Otherwise, it
  /// returns a no-op function.
  ///
  /// > [!WARNING]
  /// > Read it per call, never hoist it. Enabling and disabling a level
  /// > *swaps this field*, so a function stored in a variable is a snapshot:
  /// > captured while enabled it keeps publishing after
  /// > `logger.level = Levels.off`, and captured while disabled it stays
  /// > silent after the level is turned back on. Expose it through a getter
  /// > (`LogFn get d => _d.log;`) so every call re-reads the current
  /// > function. Note that the logger's [CustomLogger.transformer] still runs
  /// > on the stale path — only the level gate is bypassed.
  LogFn get log => _log;

  /// Returns the actual parent [Logger] instance.
  ///
  /// Throws a [StateError] if this level logger hasn't been registered.
  @protected
  Logger get logger => _logger ?? (throw StateError('Logger is not attached'));

  /// Returns `true` if logging is currently enabled for this specific level.
  bool get isEnabled => !identical(_log, _noLog);

  /// Returns the custom log publisher assigned to this particular level.
  ///
  /// Reading it and calling `publish` yourself bypasses
  /// [CustomLogger.transformer]: masking, redaction and the drop-on-`null`
  /// rule all live in [publishLog], not in the publisher. The transformer is
  /// a convenience applied on the library's own path, not an enforced
  /// boundary — if secrets must never reach a sink, put the masking in the
  /// publisher (or wrap it in a `TransformPublisher`) rather than relying on
  /// every caller going through the logger.
  CustomLogPublisher<Log> get publisher => _publisher;

  /// Whether this level has a publisher that actually goes somewhere.
  ///
  /// `false` means the level still sits on the no-op publisher every level
  /// starts on: [isEnabled] can be `true` and the log function can return
  /// normally while nothing is ever written. That combination is otherwise
  /// undetectable from the outside, because the no-op publisher is private,
  /// so this is the check to assert on when a level looks silent.
  bool get hasPublisher => _hasPublisher;

  /// Whether this level holds a publisher of its own rather than one taken
  /// from above.
  ///
  /// `true` after `logger[level].publisher = ...`; [relink] on this level
  /// turns it back to `false`, and so does [CustomLogger.relink] on the
  /// whole logger, which drops every other level's pin along with it. See
  /// [hasPublisher] for the other question — whether the publisher goes
  /// anywhere at all.
  ///
  /// Only that assignment pins. A publisher handed to the constructor is
  /// a starting value, not a pin: it is `false` here, and both an
  /// inherited publisher and this logger's common [CustomLogger.publisher]
  /// setter replace it.
  bool get hasOwnPublisher => _hasOwnPublisher;

  void _setPublisher(CustomLogPublisher<Log> publisher) {
    _publisher = publisher;
    _hasPublisher = true;
  }

  void _resetPublisher() {
    _publisher = const CustomLogPublisher.noOp();
    _hasPublisher = false;
  }

  /// Sets the log message publisher for a specific level.
  ///
  /// ```dart
  /// log[Levels.info].publisher = CustomLogPublisher((log) => print(log));
  /// ```
  ///
  /// Assigning here pins this level: it keeps this publisher until
  /// [relink] is called, and neither a parent update nor this logger's own
  /// common [CustomLogger.publisher] setter overrules it. The other levels
  /// keep following the parent, and [CustomLogger.publisherLinked] stays
  /// up — the pin is per level, the link is per logger.
  set publisher(CustomLogPublisher<Log> publisher) {
    // We set the publisher via the logger to update the publisher in the
    // subloggers.
    logger._setLevelPublisher(level, publisher);
  }

  /// Drops the publisher this level holds of its own and takes what the
  /// chain offers again: the parent's publisher for exactly this level,
  /// then the last common publisher assigned anywhere up the chain.
  ///
  /// When there is nothing to take — a root logger that was only ever
  /// configured per level — this level goes back to the no-op publisher
  /// and [hasPublisher] becomes `false`. Handing it the publisher chosen
  /// for some *other* level would be an invention.
  ///
  /// Linked subloggers come along, in that case as in every other: their
  /// own unpinned copy of this level arrives at the no-op publisher too,
  /// rather than keeping what it used to inherit from here. An unpinned
  /// level always equals what the chain offers, and reporting
  /// [hasPublisher] for a publisher that goes nowhere is exactly the
  /// state that getter exists to expose.
  ///
  /// Returns nothing, unlike [CustomLogger.relink]: that one answers
  /// `false` when there is no parent to follow, while a level always has
  /// something above it — at worst its own logger.
  void relink() => logger._relinkLevel(level);

  /// Publishes [log], first applying the logger's
  /// [CustomLogger.transformer].
  ///
  /// Returning `null` from the transformer drops the log. A throwing
  /// transformer also drops it (fail-closed: the untransformed log is
  /// never published).
  ///
  /// Every error caught here — a throwing transformer, a reentrancy guard
  /// violation, a throwing publisher — is routed through
  /// [CustomLogger.onError]. With no handler set, the first two go to the
  /// current zone via [Zone.handleUncaughtError] and a publisher error keeps
  /// propagating out of the logging call, which is where it has always
  /// surfaced.
  ///
  /// Subclasses must call this from [processLog] instead of
  /// `publisher.publish(...)` — otherwise [CustomLogger.transformer] is
  /// ignored.
  @protected
  void publishLog(Log log) {
    // Captured once: re-reading `logger` would let a level logger that got
    // re-attached mid-transform clear the guard on the wrong owner and leave
    // the original latched forever.
    final owner = logger;
    final onError = owner.onError;
    var published = log;

    if (owner._transformer case final transformer?) {
      if (owner._transforming) {
        _reportGuardViolation(
          onError,
          'A log transformer must not log through its own logger; '
          'the nested log was dropped',
        );

        return;
      }

      final Log? transformed;
      owner._transforming = true;
      try {
        transformed = transformer(log);
      } on Object catch (error, stackTrace) {
        _report(onError, error, stackTrace);

        return;
      } finally {
        // Scoped to the transformer alone; the publish path below has its
        // own guard. (A chained TransformPublisher was never at risk here:
        // it keeps its own flag, on its own object.)
        owner._transforming = false;
      }

      if (transformed == null) {
        return;
      }
      published = transformed;
    }

    if (_publishing) {
      _reportGuardViolation(
        onError,
        'A publisher must not log through the level it publishes for; '
        'the nested log was dropped',
      );

      return;
    }

    _publishing = true;
    try {
      _publisher.publish(published);
    } on Object catch (error, stackTrace) {
      // Without a handler the error keeps propagating out of the logging
      // call, as it always has; with one, logging cannot break its caller.
      if (onError == null) {
        rethrow;
      }
      _invokeHandler(onError, error, stackTrace);
    } finally {
      _publishing = false;
    }
  }

  static void _reportGuardViolation(
    void Function(Object error, StackTrace stackTrace)? onError,
    String message,
  ) =>
      _report(onError, StateError(message), StackTrace.current);

  static void _report(
    void Function(Object error, StackTrace stackTrace)? onError,
    Object error,
    StackTrace stackTrace,
  ) {
    if (onError == null) {
      Zone.current.handleUncaughtError(error, stackTrace);

      return;
    }

    _invokeHandler(onError, error, stackTrace);
  }

  static void _invokeHandler(
    void Function(Object error, StackTrace stackTrace) onError,
    Object error,
    StackTrace stackTrace,
  ) {
    try {
      onError(error, stackTrace);
    } on Object catch (handlerError, handlerStackTrace) {
      // A throwing error handler must not wedge logging.
      Zone.current.handleUncaughtError(handlerError, handlerStackTrace);
    }
  }

  void _attach(Logger logger) {
    if (_logger case final attached? when !identical(attached, logger)) {
      throw StateError(
        'This level logger is already registered in another logger; '
        'sharing one would route this logger through the publisher and '
        'transformer of the other',
      );
    }
    _logger = logger;
    _toggle(logger.level <= level);
  }

  void _toggle(bool enabled) {
    // No-op when the state is unchanged. `processLog` allocates a fresh
    // closure in every documented pattern, so re-toggling an already-enabled
    // level was pure waste (measured: 3M closures for 50 level assignments
    // over 20k linked subloggers) and it changed the identity of a function
    // a caller may have hoisted.
    if (enabled == isEnabled) {
      return;
    }

    _log = enabled ? processLog : _noLog;
  }
}
