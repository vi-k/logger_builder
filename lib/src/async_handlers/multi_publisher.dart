/// A handler that delegates an event to multiple publishers simultaneously.
///
/// This class is useful when you want to route the same data (such as a log
/// event) to several different destinations, like a console printer, a file
/// writer, or a remote logging service, using a single overarching publisher.
///
/// Example usage:
///
/// ```dart
/// final consolePrinter = (String data) => print('Console: $data');
/// final filePrinter = (String data) => print('File: $data'); // e.g. writing to file
///
/// final multiPublisher = MultiPublisher<String>([
///   consolePrinter,
///   filePrinter,
/// ]);
///
/// log.printer = multiPublisher.publish;
/// ```
base class MultiPublisher<T extends Object?> {
  final List<void Function(T event)> _publishers;

  /// Creates a [MultiPublisher] with the specified list of [_publishers].
  ///
  /// When [publish] is called, the `event` will be passed to each publisher
  /// in the provided list in the sequence they were provided.
  MultiPublisher(List<void Function(T event)> publishers)
      : _publishers = publishers;

  /// Publishes the given [event] to all registered publishers.
  ///
  /// This iterates through the list of registered publishers and synchronously
  /// passes the [event] to each one.
  void publish(T event) {
    for (final publisher in _publishers) {
      publisher(event);
    }
  }
}
