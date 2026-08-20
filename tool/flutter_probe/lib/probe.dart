// The shapes a Flutter consumer actually builds: a logger, a sublogger made
// through the constructor, and both buffered base classes with the settings
// that arrived in 0.7.0. If a Flutter SDK ever resolves `meta` to something
// this package cannot live with, this file stops compiling.

import 'package:flutter/foundation.dart';
import 'package:logger_builder/logger_builder.dart';

typedef LogFn = bool Function(
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
});

final class Log extends CustomLog {
  final LazyString _lazyMessage;

  Log(
    super.levelLogger, {
    required Object? message,
    super.error,
    super.stackTrace,
    super.zone,
  }) : _lazyMessage = LazyString(message);

  String get message => _lazyMessage.value;
}

final class LevelLogger
    extends CustomLevelLogger<Logger, LevelLogger, LogFn, Log> {
  LevelLogger({required super.level, required super.name})
      : super(noLog: (_, {error, stackTrace}) => true);

  @override
  LogFn get processLog => (message, {error, stackTrace}) {
        publishLog(
          Log(this, message: message, error: error, stackTrace: stackTrace),
        );

        return true;
      };
}

final class Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log> {
  Logger();

  // A sublogger is made by constructor: the package has no `sub(...)` method.
  Logger.sub(super.parent) : super.sub();

  @override
  void registerLevels() {
    registerLevel(_i);
    registerLevel(_e);
  }

  final LevelLogger _i = LevelLogger(level: Levels.info, name: 'info');
  final LevelLogger _e = LevelLogger(level: Levels.error, name: 'error');

  LogFn get i => _i.log;
  LogFn get e => _e.log;
}

final class ProbePublisher extends AsyncPublisherWithBufferBase<Log> {
  ProbePublisher()
      : super(maxRetries: 10, maxQueueSize: 1000, onDropped: _report);

  static void _report(List<Log> logs) => debugPrint('dropped ${logs.length}');

  @override
  Future<void> handle(List<Log> logs, List<Log> retryBuffer) async {
    debugPrint(logs.map((log) => log.message).join('\n'));
  }
}

final class ProbeParamPublisher
    extends AsyncPublisherWithBufferAndParamBase<String, Log> {
  ProbeParamPublisher() : super(maxRetries: 10, maxQueueSize: 1000);

  @override
  Future<void> handle(
    List<(String, Log)> entries,
    List<(String, Log)> retryBuffer,
  ) async {
    for (final (param, log) in entries) {
      debugPrint('$param: ${log.message}');
    }
  }
}

/// Touches every shape above, so nothing here is dead code the compiler
/// could skip.
Future<void> probe() async {
  final publisher = ProbePublisher();
  final byParam = ProbeParamPublisher();

  final root = Logger()
    ..level = Levels.all
    ..publisher = publisher;
  final child = Logger.sub(root)
    ..[Levels.error].publisher = byParam.withParam('child');

  root.i('root speaks');
  child.e('child speaks');

  await publisher.close();
  await byParam.close();
}
