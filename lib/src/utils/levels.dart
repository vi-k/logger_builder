/// Logging levels.
///
/// These are not absolute values, but simply constants for convenience. You
/// can use them or set your own.
///
/// Leave only the extreme values untouched: [all] and [off]. Let your values
/// be in between them.
abstract final class Levels {
  /// The lowest possible threshold: every level is enabled.
  static const int all = 0;

  /// Highly detailed tracing (same value as in `package:logging`).
  static const int finest = 300;

  /// Fairly detailed tracing (same value as in `package:logging`).
  static const int finer = 400;

  /// Tracing information (same value as in `package:logging`).
  static const int fine = 500;

  /// Static configuration messages (same value as in `package:logging`).
  static const int config = 700;

  /// Informational messages (same value as in `package:logging`).
  static const int info = 800;

  /// Potential problems (same value as in `package:logging`).
  static const int warning = 900;

  /// Serious failures (same value as in `package:logging`).
  static const int severe = 1000;

  /// Extra loud failures (same value as in `package:logging`).
  static const int shout = 1200;

  /// Alias for [finest].
  static const int trace = finest;

  /// Alias for [finer].
  static const int verbose = finer;

  /// Alias for [fine].
  static const int debug = fine;

  /// Alias for [severe].
  static const int error = severe;

  /// Alias for [shout].
  static const int critical = shout;

  /// The highest possible threshold: logging is completely disabled.
  static const int off = 2000;
}
