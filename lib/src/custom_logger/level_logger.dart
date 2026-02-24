part of 'logger.dart';

/// An abstract base class representing a specific log level for
/// a [CustomLogger].
///
/// Instances of this class handle logging operations for a particular log
/// level. They manage the conversion of log data into [CustomLogEntry] objects
/// using a builder, and dispatching the formatted output to a printer.
///
/// When the logger's level is above this level logger's configured [level],
/// calls to the actual logic will be replaced with a no-op function to avoid
/// unnecessary computations.
///
/// It takes the same generic type parameters as [CustomLogger].
abstract class CustomLevelLogger<
    L extends CustomLogger<L, LL, Log, Ent, Out>,
    LL extends CustomLevelLogger<L, LL, Log, Ent, Out>,
    Log extends Function,
    Ent extends CustomLogEntry,
    Out extends Object?> {
  /// Numerical value of the level of this [LL] logger.
  ///
  /// Greater than 0 and less than 2000
  ///
  /// See [Levels].
  final int level;

  /// Name of the level of this [LL] logger.
  final String name;

  /// Short name of the level of this [LL] logger.
  ///
  /// Default is equal to the first letter of the name.
  final String shortName;

  /// Plug function when logging is disabled for this level.
  ///
  /// The function must be passed through the constructor and for this reason
  /// must be static or global.
  final Log _noLog;

  /// Link to [L] logger.
  ///
  /// The [LL] logger is attached to [L] logger using the
  /// [CustomLogger.registerLevel] method.
  L? _logger;

  /// Current log function.
  ///
  /// If logging is enabled for this level, it is equal to [processLog].
  /// Otherwise, it is equal to [_noLog].
  Log _log;

  /// Current builder.
  CustomLogBuilder<Ent, Out> _builder;

  /// Current printer.
  CustomLogPrinter<Out> _printer;

  CustomLevelLogger({
    required this.level,
    required this.name,
    String? shortName,
    required Log noLog,
    required CustomLogBuilder<Ent, Out> builder,
    required CustomLogPrinter<Out> printer,
  })  : assert(name.isNotEmpty, 'name must be non-empty'),
        shortName = shortName ?? name[0],
        _noLog = noLog,
        _log = noLog,
        _builder = builder,
        _printer = printer;

  @protected
  Log get processLog;

  Log get log => _log;

  @protected
  L get logger => _logger ?? (throw StateError('Logger is not attached'));

  bool get isEnabled => !identical(_log, _noLog);

  CustomLogBuilder<Ent, Out> get builder => _builder;

  /// Sets the log message builder for a specific level.
  ///
  /// ```dart
  /// log[Levels.info].builder = (entry) {
  ///   return '${entry.levelName.toUpperCase()}: ${entry.message}';
  /// };
  /// ```
  set builder(CustomLogBuilder<Ent, Out> builder) {
    // We set the builder via the logger to update the builder in the
    // subloggers.
    logger._setLevelBuilder(level, builder);
  }

  CustomLogPrinter<Out> get printer => _printer;

  /// Sets the log message printer for a specific level.
  ///
  /// ```dart
  /// log[Levels.info].printer = print;
  /// ```
  set printer(CustomLogPrinter<Out> printer) {
    // We set the printer via the logger to update the printer in the
    // subloggers.
    logger._setLevelPrinter(level, printer);
  }

  void _attach(L logger) {
    _logger = logger;
    _toggle(logger.level <= level);
  }

  void _toggle(bool enabled) {
    _log = enabled ? processLog : _noLog;
  }
}
