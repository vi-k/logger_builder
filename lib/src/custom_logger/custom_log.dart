import 'dart:async';

import 'package:meta/meta.dart';

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
  ///
  /// The library itself never reads this field — it exists for custom
  /// formatters and handlers. Typical uses inside your `handle`/`format`:
  /// reading zone-local values (`log.zone[#requestId]`) or running code in
  /// the zone of the logging call site (`log.zone.run(() => ...)`).
  ///
  /// Note that the zone (and everything it captured) is retained as long as
  /// the log object is alive — for buffered publishers, until the batch is
  /// processed.
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
  }) : level = levelLogger.level,
       levelName = levelLogger.name,
       shortLevelName = levelLogger.shortName,
       stackTrace = stackTrace ?? stackTraceFromError(error),
       zone = zone ?? Zone.current;

  /// Creates a copy of [original] with the given [error] and [stackTrace].
  ///
  /// [level], [levelName], [shortLevelName] and [zone] are taken from
  /// [original]; [error] and [stackTrace] are assigned verbatim — unlike
  /// the main constructor, no stack trace is derived from [error]. Intended
  /// for subclass `copyWith` implementations: a copy is not a new log
  /// event, so no new identity (number, time) should be minted.
  @protected
  CustomLog.copy(
    CustomLog original, {
    required this.error,
    required this.stackTrace,
  }) : level = original.level,
       levelName = original.levelName,
       shortLevelName = original.shortLevelName,
       zone = original.zone;

  /// Attempts to extract a [StackTrace] securely from an [error] object
  /// if it is of type [Error].
  static StackTrace? stackTraceFromError(Object? error) =>
      error is Error ? error.stackTrace : null;
}

/// Transforms a log event before it is published.
///
/// Returning a (possibly modified) log publishes it instead of the
/// original; returning `null` drops the log entirely. Used by
/// `CustomLogger.transformer` and `TransformPublisher` — primarily for
/// security: masking secrets and PII before the log reaches any output.
///
/// A transformer must not log into the pipeline it is part of: the nested
/// call would re-enter the transformer and recurse until the stack is
/// exhausted. Such a call is detected and dropped with a [StateError] —
/// see `CustomLogger.transformer` and `TransformPublisher`.
typedef LogTransformer<Log extends CustomLog> = Log? Function(Log log);
