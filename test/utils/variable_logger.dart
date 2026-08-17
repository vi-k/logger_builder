import 'package:logger_builder/logger_builder.dart';

/// A test fixture logger whose set of registered levels is configurable,
/// allowing hierarchies where a sublogger lacks some of the parent's levels.
typedef VarLogFn = bool Function(Object? message);

final class VarLog extends CustomLog {
  final LazyStringOrNull _lazyMessage;

  VarLog(super.levelLogger, {required Object? message})
    : _lazyMessage = LazyStringOrNull(message);

  String? get message => _lazyMessage.value;
}

final class VarLevelLogger
    extends CustomLevelLogger<VarLogger, VarLevelLogger, VarLogFn, VarLog> {
  VarLevelLogger({required super.level, required super.name, super.shortName})
    : super(noLog: (_) => true);

  @override
  VarLogFn get processLog => (message) {
    publishLog(VarLog(this, message: message));
    return true;
  };
}

base class VarLogger
    extends CustomLogger<VarLogger, VarLevelLogger, VarLogFn, VarLog> {
  final List<int> levelValues;

  VarLogger(this.levelValues);

  VarLogger.sub(super.parent, this.levelValues) : super.sub();

  @override
  void registerLevels() {
    for (final level in levelValues) {
      registerLevel(VarLevelLogger(level: level, name: 'L$level'));
    }
  }

  VarLogFn logAt(int level) => this[level].log;

  /// Exposes the protected [registerLevel] so tests can add a level after
  /// construction.
  void addLevel(int level) =>
      registerLevel(VarLevelLogger(level: level, name: 'L$level'));

  /// Exposes the protected [registerSublogger] so a test can build a cyclic
  /// sublogger graph, which is what the `*Linked` flags quietly protect
  /// against.
  void attach(VarLogger sublogger) => registerSublogger(sublogger);
}

/// Registers a level logger handed in from outside, so a test can try to
/// register the same instance in two loggers.
///
/// [shared] is an initializing formal, so it is assigned before the
/// superclass constructor calls [registerLevels].
final class SharedLevelLogger extends VarLogger {
  final VarLevelLogger shared;

  SharedLevelLogger(this.shared) : super(const []);

  @override
  void registerLevels() => registerLevel(shared);
}
