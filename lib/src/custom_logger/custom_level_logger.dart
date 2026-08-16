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
  /// Greater than 0 and less than 2000.
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
  /// The [name] must not be empty, otherwise an [ArgumentError] is thrown.
  /// When [shortName] is omitted, the first character (code point) of [name]
  /// is used.
  CustomLevelLogger({
    required this.level,
    required String name,
    String? shortName,
    required LogFn noLog,
    CustomLogPublisher<Log>? publisher,
  })  : name = _checkName(name),
        shortName = shortName ?? _firstCharacter(name),
        _noLog = noLog,
        _log = noLog,
        _publisher = publisher ?? const CustomLogPublisher.noOp();

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
    var published = log;

    if (logger._transformer case final transformer?) {
      if (logger._transforming) {
        Zone.current.handleUncaughtError(
          StateError(
            'A log transformer must not log through its own logger; '
            'the nested log was dropped',
          ),
          StackTrace.current,
        );

        return;
      }

      final Log? transformed;
      logger._transforming = true;
      try {
        transformed = transformer(log);
      } on Object catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);

        return;
      } finally {
        // Released before publishing, so a TransformPublisher further down
        // the chain is not mistaken for a reentrant call.
        logger._transforming = false;
      }

      if (transformed == null) {
        return;
      }
      published = transformed;
    }

    _publisher.publish(published);
  }

  void _attach(Logger logger) {
    _logger = logger;
    _toggle(logger.level <= level);
  }

  void _toggle(bool enabled) {
    _log = enabled ? processLog : _noLog;
  }
}
