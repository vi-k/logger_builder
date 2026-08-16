part of 'custom_logger.dart';

/// An abstract base class representing a specific log level for
/// a [CustomLogger].
///
/// Instances of this class handle logging operations for a particular log
/// level. They manage the conversion of log data into [CustomLog] objects
/// using a builder, and dispatching the formatted output to a printer.
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
        _publisher = publisher ?? const CustomLogPublisher.noOp();

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
  LogFn get log => _log;

  /// Returns the actual parent [Logger] instance.
  ///
  /// Throws a [StateError] if this level logger hasn't been registered.
  @protected
  Logger get logger => _logger ?? (throw StateError('Logger is not attached'));

  /// Returns `true` if logging is currently enabled for this specific level.
  bool get isEnabled => !identical(_log, _noLog);

  /// Returns the custom log publisher assigned to this particular level.
  CustomLogPublisher<Log> get publisher => _publisher;

  /// Sets the log message publisher for a specific level.
  ///
  /// ```dart
  /// log[Levels.info].publisher = CustomLogPublisher((log) => print(log));
  /// ```
  ///
  /// Assigning here also detaches the whole logger from its parent's
  /// publishers — the link flag is per logger, not per level — so a single
  /// per-level assignment stops this logger from inheriting any publisher
  /// change from the parent until [CustomLogger.relink] is called.
  set publisher(CustomLogPublisher<Log> publisher) {
    // We set the publisher via the logger to update the publisher in the
    // subloggers.
    logger._setLevelPublisher(level, publisher);
  }

  /// Publishes [log], first applying the logger's
  /// [CustomLogger.transformer].
  ///
  /// Returning `null` from the transformer drops the log. A throwing
  /// transformer also drops it (fail-closed: the untransformed log is
  /// never published) and reports the error to the current zone via
  /// [Zone.handleUncaughtError].
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
    var published = log;

    if (owner._transformer case final transformer?) {
      if (owner._transforming) {
        _reportGuardViolation(
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
        Zone.current.handleUncaughtError(error, stackTrace);

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

    if (owner._publishing) {
      _reportGuardViolation(
        'A publisher must not log through the logger it publishes for; '
        'the nested log was dropped',
      );

      return;
    }

    owner._publishing = true;
    try {
      _publisher.publish(published);
    } finally {
      owner._publishing = false;
    }
  }

  static void _reportGuardViolation(String message) {
    Zone.current.handleUncaughtError(StateError(message), StackTrace.current);
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
    _log = enabled ? processLog : _noLog;
  }
}
