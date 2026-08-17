// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import '../../custom_logger/custom_log.dart';
import '../../custom_logger/custom_log_publisher.dart';
import '../async_publisher.dart';

/// Internal adapter: a [CustomLogPublisher] that forwards each log with
/// a fixed parameter into an underlying parameterized publisher.
///
/// Implements [Flushable] and [Closable] by delegating to the owning
/// publisher. Without them the adapter looked like an ordinary publisher to
/// `MultiPublisher` and `TransformPublisher`, which select members with a
/// type test: the adapter was skipped, `close()` reported success, and the
/// whole shared queue was lost. Both delegates are idempotent on the owner
/// side, so closing one adapter closes the shared queue — the only coherent
/// semantics when several adapters feed one queue.
///
/// Not exported by the package.
final class AsyncParamPublisher<Param extends Object?, Log extends CustomLog>
    implements CustomLogPublisher<Log>, Flushable, Closable {
  final void Function(Param param, Log log) _publish;
  final Future<void> Function() _flush;
  final Future<void> Function() _close;
  final Param _param;

  AsyncParamPublisher(this._publish, this._param, this._flush, this._close);

  @override
  void publish(Log log) => _publish(_param, log);

  @override
  Future<void> flush() => _flush();

  @override
  Future<void> close() => _close();
}
