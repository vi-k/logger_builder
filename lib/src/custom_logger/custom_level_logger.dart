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
abstract class CustomLevelLogger<
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
  /// The function must be passed through the constructor and for this reason
  /// must be static or global.
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

  CustomLevelLogger({
    required this.level,
    required this.name,
    String? shortName,
    required LogFn noLog,
    CustomLogPublisher<Log>? publisher,
  })  : assert(name.isNotEmpty, 'name must be non-empty'),
        shortName = shortName ?? name[0],
        _noLog = noLog,
        _log = noLog,
        _publisher = publisher ?? const CustomLogPublisher.noOp();

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
  /// log[Levels.info].publisher = print; // +++
  /// ```
  set publisher(CustomLogPublisher<Log> publisher) {
    // We set the publisher via the logger to update the publisher in the
    // subloggers.
    logger._setLevelPublisher(level, publisher);
  }

  void _attach(Logger logger) {
    _logger = logger;
    _toggle(logger.level <= level);
  }

  void _toggle(bool enabled) {
    _log = enabled ? processLog : _noLog;
  }
}
