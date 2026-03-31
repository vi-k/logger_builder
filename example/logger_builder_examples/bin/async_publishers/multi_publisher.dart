import 'package:ansi_escape_codes/ansi_escape_codes.dart';
import 'package:logger_builder/logger_builder.dart';
import 'package:logger_builder_examples/console.dart';
import 'package:logger_builder_examples/simple_logger.dart';

Future<void> main() async {
  final log = Logger()..level = Levels.all;

  final multiPublisher = MultiPublisher<Log>([
    CustomLogPublisher(
      (log) => print('$fgGreen[CustomLogPublisher] ${log.message}$reset'),
    ),
    AsyncPublisher((entry) async {
      print('$fgYellow[AsyncPublisher] ${entry.message}$reset');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }),
    AsyncPublisherWithBuffer((logs, _) async {
      print(
        '$fgMagenta'
        '[AsyncPublisherWithBuffer] Handle ${logs.length} message(s):'
        '$reset',
      );
      for (final log in logs) {
        print(
          '  $fgMagenta'
          '[AsyncPublisherWithBuffer] ${log.message}'
          '$reset',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }),
  ]);

  log.publisher = multiPublisher;

  log.d('1 Debug message');
  log.i('1 Info message');
  log.e('1 Error message');
  await null;

  log.d('2 Debug message');
  log.i('2 Info message');
  log.e('2 Error message');

  await multiPublisher.flush();

  title('end of main');
}
