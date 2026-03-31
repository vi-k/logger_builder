import 'custom_log.dart';

/// An interface for publishing or outputting emitted log events.
///
/// Log publishers encapsulate the logic of what to do with a [Log] after
/// it has been created and passed the level filtering. This can include
/// printing to stdout, writing to a file, or sending it over a network.
// ignore: one_member_abstracts
abstract interface class CustomLogPublisher<Log extends CustomLog> {
  /// Creates a publisher from a simple function.
  const factory CustomLogPublisher(void Function(Log log) publish) =
      _CustomLogPublisherImpl;

  /// Creates a no-op publisher that ignores all received logs.
  const factory CustomLogPublisher.noOp() = _NoOpPublisher;

  /// Publishes the given [log] event.
  void publish(Log log);
}

final class _NoOpPublisher<Log extends CustomLog>
    implements CustomLogPublisher<Log> {
  const _NoOpPublisher();

  @override
  void publish(covariant Object? log) {}
}

final class _CustomLogPublisherImpl<Log extends CustomLog>
    implements CustomLogPublisher<Log> {
  final void Function(Log log) _publish;

  const _CustomLogPublisherImpl(this._publish);

  @override
  void publish(Log log) {
    _publish(log);
  }
}

/// A convenience implementation of [CustomLogPublisher] that supports
/// transforming a log event before ultimately emitting it.
///
/// Uses [format] to convert the [Log] into an [Out] object, which is then
/// passed into [output] for actual logging (e.g. printing).
final class CustomLogFormatter<Log extends CustomLog, Out extends Object?>
    implements CustomLogPublisher<Log> {
  final Out Function(Log log) format;
  final void Function(Out out) output;

  const CustomLogFormatter({
    required this.format,
    required this.output,
  });

  @override
  void publish(Log log) {
    output(format(log));
  }
}
