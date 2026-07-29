// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import '../../custom_logger/custom_log.dart';
import '../../custom_logger/custom_log_publisher.dart';

/// Internal adapter: a [CustomLogPublisher] that forwards each log with
/// a fixed parameter into an underlying parameterized publisher.
///
/// Not exported by the package.
final class AsyncParamPublisher<Param extends Object?, Log extends CustomLog>
    implements CustomLogPublisher<Log> {
  final void Function(Param param, Log log) _publish;
  final Param _param;

  AsyncParamPublisher(this._publish, this._param);

  @override
  void publish(Log log) => _publish(_param, log);
}
