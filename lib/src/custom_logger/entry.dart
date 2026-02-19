import 'dart:async';

import 'logger.dart';

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
  }) : level = levelLogger.level,
       levelName = levelLogger.name,
       shortLevelName = levelLogger.shortName,
       stackTrace = stackTrace ?? stackTraceFromError(error),
       zone = zone ?? Zone.current;

  static StackTrace? stackTraceFromError(Object? error) =>
      error is Error ? error.stackTrace : null;
}
