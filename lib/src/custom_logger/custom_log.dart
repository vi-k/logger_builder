import 'dart:async';

import 'custom_logger.dart';

/// A base representation of a single log event.
///
/// This class encapsulates information about a logging event, including the
/// [level], level names, an optional [error], its [stackTrace], and the [Zone]
/// in which the log was produced. Subclasses can extend this to include the
/// actual message content or other custom fields.
abstract base class CustomLog {
  /// The numerical severity value of this log event.
  final int level;

  /// The display name for the severity level (e.g., "INFO", "ERROR").
  final String levelName;

  /// A shortened representation of the level's display name.
  final String shortLevelName;

  /// An optional error or exception object associated with this log event.
  final Object? error;

  /// An optional stack trace associated with the error or log event.
  final StackTrace? stackTrace;

  /// The asynchronous [Zone] in which this log event was produced.
  final Zone zone;

  /// Creates a [CustomLog] instance tied to the given [levelLogger].
  ///
  /// Extracts the required level details directly from the provided
  /// [levelLogger]. If [stackTrace] is omitted but [error] is present,
  /// it attempts to extract the stack trace from the error. If [zone]
  /// is omitted, it defaults to the [Zone.current] at the time of creation.
  CustomLog(
    CustomLevelLogger levelLogger, {
    this.error,
    StackTrace? stackTrace,
    Zone? zone,
  })  : level = levelLogger.level,
        levelName = levelLogger.name,
        shortLevelName = levelLogger.shortName,
        stackTrace = stackTrace ?? stackTraceFromError(error),
        zone = zone ?? Zone.current;

  /// Attempts to extract a [StackTrace] securely from an [error] object
  /// if it is of type [Error].
  static StackTrace? stackTraceFromError(Object? error) =>
      error is Error ? error.stackTrace : null;
}
