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
        publisher.publish(VarLog(this, message: message));
        return true;
      };
}

final class VarLogger
    extends CustomLogger<VarLogger, VarLevelLogger, VarLogFn, VarLog> {
  final List<int> levels;

  VarLogger(this.levels);

  VarLogger.sub(super.parent, this.levels) : super.sub();

  @override
  void registerLevels() {
    for (final level in levels) {
      registerLevel(VarLevelLogger(level: level, name: 'L$level'));
    }
  }

  VarLogFn logAt(int level) => this[level].log;
}
