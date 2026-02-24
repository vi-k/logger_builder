import 'dart:async';

import 'logger.dart';

/// A base representation of a single log event.
///
/// This class encapsulates information about a logging event, including the
/// [level], level names, an optional [error], its [stackTrace], and the [Zone]
/// in which the log was produced. Subclasses can extend this to include the
/// actual message content or other custom fields.
abstract base class CustomLogEntry {
  final int level;
  final String levelName;
  final String shortLevelName;
  final Object? error;
  final StackTrace? stackTrace;
  final Zone zone;

  CustomLogEntry(
    CustomLevelLogger levelLogger, {
    this.error,
    StackTrace? stackTrace,
    Zone? zone,
  })  : level = levelLogger.level,
        levelName = levelLogger.name,
        shortLevelName = levelLogger.shortName,
        stackTrace = stackTrace ?? stackTraceFromError(error),
        zone = zone ?? Zone.current;

  static StackTrace? stackTraceFromError(Object? error) =>
      error is Error ? error.stackTrace : null;
}
