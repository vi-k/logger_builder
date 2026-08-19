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

/// A [VarLogger] that counts how often its `onError` getter is consulted.
///
/// The happy path of `publishLog` must not consult it at all: the handler
/// is resolved by walking the parent chain, so one read per log makes an
/// enabled log cost more the deeper the sublogger sits.
base class CountingLogger extends VarLogger {
  int onErrorReads = 0;

  CountingLogger(super.levelValues);

  CountingLogger.sub(CountingLogger super.parent, super.levelValues)
      : super.sub();

  @override
  void Function(Object error, StackTrace stackTrace)? get onError {
    onErrorReads++;

    return super.onError;
  }
}

/// A [VarLogger] that counts how often it prunes its sublogger list.
///
/// Registration must not scan the whole list every time — creating n
/// subloggers under one parent would cost O(n²), and one per request or per
/// widget is the documented pattern. The amortization is invisible in
/// behaviour and only shows up as this count.
base class PruneCountingLogger extends VarLogger {
  int pruneCount = 0;

  PruneCountingLogger(super.levelValues);

  PruneCountingLogger.sub(PruneCountingLogger super.parent, super.levelValues)
      : super.sub();

  @override
  void pruneSubloggers() {
    pruneCount++;
    super.pruneSubloggers();
  }
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
