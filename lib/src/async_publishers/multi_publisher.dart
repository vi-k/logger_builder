import 'package:logger_builder/logger_builder.dart';

/// A handler that delegates an event to multiple publishers simultaneously.
///
/// This class is useful when you want to route the same data (such as a log
/// event) to several different destinations, like a console printer, a file
/// writer, or a remote logging service, using a single overarching publisher.
///
/// Example usage:
///
/// ```dart
/// final consolePrinter = CustomLogPublisher((log) => print('Console: $log'));
/// final filePrinter = AsyncPublisher((log) async {/* write to file */});
///
/// final multiPublisher = MultiPublisher([
///   consolePrinter,
///   filePrinter,
/// ]);
///
/// log.publisher = multiPublisher;
///
/// ...
///
/// await multiPublisher.flush();
/// ```
base class MultiPublisher<Log extends CustomLog>
    implements CustomLogPublisher<Log>, HasFlush {
  final List<CustomLogPublisher<Log>> _publishers;

  MultiPublisher(List<CustomLogPublisher<Log>> publishers)
      : _publishers = publishers;

  @override
  void publish(Log log) {
    for (final publisher in _publishers) {
      publisher.publish(log);
    }
  }

  @override
  Future<void> flush() =>
      _publishers.whereType<HasFlush>().map((e) => e.flush()).wait;
}
