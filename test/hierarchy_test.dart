import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

void main() {
  group('Hierarchy', () {
    late Logger log;
    late Logger log2;
    late Logger log3;
    final buf = <String>[];

    setUp(() {
      log = Logger('root')
        ..level = Levels.all
        ..publisher = CustomLogFormatter(
          format: Logger.defaultFormat,
          output: buf.add,
        );
      log2 = log.withAddedName('first');
      log3 = log2.withAddedName('second');
    });

    tearDown(buf.clear);

    void logAll() {
      log.d('debug');
      log.i('info');
      log.e('error');
      log2.d('debug');
      log2.i('info');
      log2.e('error');
      log3.d('debug');
      log3.i('info');
      log3.e('error');
    }

    group('level', () {
      test('initial state', () {
        expect(log.level, Levels.all);
        expect(log2.level, Levels.all);
        expect(log3.level, Levels.all);
        expect(log.levelLinked, isFalse);
        expect(log2.levelLinked, isTrue);
        expect(log3.levelLinked, isTrue);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '[e] root | error',
          '[d] root | first | debug',
          '[i] root | first | info',
          '[e] root | first | error',
          '[d] root | first | second | debug',
          '[i] root | first | second | info',
          '[e] root | first | second | error',
        ]);
      });

      test('log=Levels.info', () {
        log.level = Levels.info;
        expect(log.level, Levels.info);
        expect(log2.level, Levels.info);
        expect(log3.level, Levels.info);
        expect(log.levelLinked, isFalse);
        expect(log2.levelLinked, isTrue);
        expect(log3.levelLinked, isTrue);
        logAll();
        expect(buf, [
          '[i] root | info',
          '[e] root | error',
          '[i] root | first | info',
          '[e] root | first | error',
          '[i] root | first | second | info',
          '[e] root | first | second | error',
        ]);
      });

      test('log=Levels.error', () {
        log.level = Levels.error;
        expect(log.level, Levels.error);
        expect(log2.level, Levels.error);
        expect(log3.level, Levels.error);
        expect(log.levelLinked, isFalse);
        expect(log2.levelLinked, isTrue);
        expect(log3.levelLinked, isTrue);
        logAll();
        expect(buf, [
          '[e] root | error',
          '[e] root | first | error',
          '[e] root | first | second | error',
        ]);
      });

      test('log=Levels.error + log=Levels.all', () {
        log
          ..level = Levels.error
          ..level = Levels.all;
        expect(log.level, Levels.all);
        expect(log2.level, Levels.all);
        expect(log3.level, Levels.all);
        expect(log.levelLinked, isFalse);
        expect(log2.levelLinked, isTrue);
        expect(log3.levelLinked, isTrue);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '[e] root | error',
          '[d] root | first | debug',
          '[i] root | first | info',
          '[e] root | first | error',
          '[d] root | first | second | debug',
          '[i] root | first | second | info',
          '[e] root | first | second | error',
        ]);
      });

      group('unlink level log2', () {
        setUp(() {
          log2.level = log2.level;
        });

        test('log=Levels.error', () {
          log.level = Levels.error;
          expect(log.level, Levels.error);
          expect(log2.level, Levels.all);
          expect(log3.level, Levels.all);
          expect(log.levelLinked, isFalse);
          expect(log2.levelLinked, isFalse);
          expect(log3.levelLinked, isTrue);
          logAll();
          expect(buf, [
            '[e] root | error',
            '[d] root | first | debug',
            '[i] root | first | info',
            '[e] root | first | error',
            '[d] root | first | second | debug',
            '[i] root | first | second | info',
            '[e] root | first | second | error',
          ]);
        });

        test('log2.level=Levels.error', () {
          log2.level = Levels.error;
          expect(log.level, Levels.all);
          expect(log2.level, Levels.error);
          expect(log3.level, Levels.error);
          expect(log.levelLinked, isFalse);
          expect(log2.levelLinked, isFalse);
          expect(log3.levelLinked, isTrue);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '[i] root | info',
            '[e] root | error',
            '[e] root | first | error',
            '[e] root | first | second | error',
          ]);
        });

        test('log2.level=Levels.error + log2.level=Levels.all', () {
          log2
            ..level = Levels.error
            ..level = Levels.all;
          expect(log.level, Levels.all);
          expect(log2.level, Levels.all);
          expect(log3.level, Levels.all);
          expect(log.levelLinked, isFalse);
          expect(log2.levelLinked, isFalse);
          expect(log3.levelLinked, isTrue);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '[i] root | info',
            '[e] root | error',
            '[d] root | first | debug',
            '[i] root | first | info',
            '[e] root | first | error',
            '[d] root | first | second | debug',
            '[i] root | first | second | info',
            '[e] root | first | second | error',
          ]);
        });

        group('unlink level log3', () {
          setUp(() {
            log3.level = log3.level;
          });

          test('log=Levels.error', () {
            log.level = Levels.error;
            expect(log.level, Levels.error);
            expect(log2.level, Levels.all);
            expect(log3.level, Levels.all);
            expect(log.levelLinked, isFalse);
            expect(log2.levelLinked, isFalse);
            expect(log3.levelLinked, isFalse);
            logAll();
            expect(buf, [
              '[e] root | error',
              '[d] root | first | debug',
              '[i] root | first | info',
              '[e] root | first | error',
              '[d] root | first | second | debug',
              '[i] root | first | second | info',
              '[e] root | first | second | error',
            ]);
          });

          test('log2.level=Levels.error', () {
            log2.level = Levels.error;
            expect(log.level, Levels.all);
            expect(log2.level, Levels.error);
            expect(log3.level, Levels.all);
            expect(log.levelLinked, isFalse);
            expect(log2.levelLinked, isFalse);
            expect(log3.levelLinked, isFalse);
            logAll();
            expect(buf, [
              '[d] root | debug',
              '[i] root | info',
              '[e] root | error',
              '[e] root | first | error',
              '[d] root | first | second | debug',
              '[i] root | first | second | info',
              '[e] root | first | second | error',
            ]);
          });

          test('log3.level=Levels.error', () {
            log3.level = Levels.error;
            expect(log.level, Levels.all);
            expect(log2.level, Levels.all);
            expect(log3.level, Levels.error);
            expect(log.levelLinked, isFalse);
            expect(log2.levelLinked, isFalse);
            expect(log3.levelLinked, isFalse);
            logAll();
            expect(buf, [
              '[d] root | debug',
              '[i] root | info',
              '[e] root | error',
              '[d] root | first | debug',
              '[i] root | first | info',
              '[e] root | first | error',
              '[e] root | first | second | error',
            ]);
          });
        });
      });
    });

    group('custom formatter', () {
      void logAll() {
        log.d('debug');
        log.i('info');
        log2.d('debug');
        log2.i('info');
        log3.d('debug');
        log3.i('info');
      }

      CustomLogPublisher<Log> customFormatter(String prefix) =>
          CustomLogFormatter(
            format: (log) => '$prefix ${Logger.defaultFormat(log)}',
            output: buf.add,
          );

      test('initial state', () {
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isTrue);
        expect(log3.publisherLinked, isTrue);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '[d] root | first | debug',
          '[i] root | first | info',
          '[d] root | first | second | debug',
          '[i] root | first | second | info',
        ]);
      });

      test('log=custom builder', () {
        log.publisher = customFormatter('+');
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isTrue);
        expect(log3.publisherLinked, isTrue);
        logAll();
        expect(buf, [
          '+ [d] root | debug',
          '+ [i] root | info',
          '+ [d] root | first | debug',
          '+ [i] root | first | info',
          '+ [d] root | first | second | debug',
          '+ [i] root | first | second | info',
        ]);
      });

      test('log2=custom builder', () {
        log2.publisher = customFormatter('+');
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isFalse);
        expect(log3.publisherLinked, isTrue);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '+ [d] root | first | debug',
          '+ [i] root | first | info',
          '+ [d] root | first | second | debug',
          '+ [i] root | first | second | info',
        ]);
      });

      test('log3=custom builder', () {
        log3.publisher = customFormatter('+');
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isTrue);
        expect(log3.publisherLinked, isFalse);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '[d] root | first | debug',
          '[i] root | first | info',
          '+ [d] root | first | second | debug',
          '+ [i] root | first | second | info',
        ]);
      });

      test(
        'log3=custom builder + log2=custom builder + log=custom builder',
        () {
          log3.publisher = customFormatter('*');
          log2.publisher = customFormatter('+');
          log.publisher = customFormatter('#');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isFalse);
          expect(log3.publisherLinked, isFalse);
          logAll();
          expect(buf, [
            '# [d] root | debug',
            '# [i] root | info',
            '+ [d] root | first | debug',
            '+ [i] root | first | info',
            '* [d] root | first | second | debug',
            '* [i] root | first | second | info',
          ]);
        },
      );

      group('on levels', () {
        test('log.info=custom builder', () {
          log[Levels.info].publisher = customFormatter('+');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isTrue);
          expect(log3.publisherLinked, isTrue);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '+ [i] root | info',
            '[d] root | first | debug',
            '+ [i] root | first | info',
            '[d] root | first | second | debug',
            '+ [i] root | first | second | info',
          ]);
        });

        test('log2.info=custom builder', () {
          log2[Levels.info].publisher = customFormatter('+');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isFalse);
          expect(log3.publisherLinked, isTrue);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '[i] root | info',
            '[d] root | first | debug',
            '+ [i] root | first | info',
            '[d] root | first | second | debug',
            '+ [i] root | first | second | info',
          ]);
        });

        test('log3.info=custom builder', () {
          log3[Levels.info].publisher = customFormatter('+');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isTrue);
          expect(log3.publisherLinked, isFalse);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '[i] root | info',
            '[d] root | first | debug',
            '[i] root | first | info',
            '[d] root | first | second | debug',
            '+ [i] root | first | second | info',
          ]);
        });

        test(
          'log3.info=custom builder + log2.info=custom builder + log.info=custom builder',
          () {
            log3[Levels.info].publisher = customFormatter('*');
            log2[Levels.info].publisher = customFormatter('+');
            log[Levels.info].publisher = customFormatter('#');
            expect(log.publisherLinked, isFalse);
            expect(log2.publisherLinked, isFalse);
            expect(log3.publisherLinked, isFalse);
            logAll();
            expect(buf, [
              '[d] root | debug',
              '# [i] root | info',
              '[d] root | first | debug',
              '+ [i] root | first | info',
              '[d] root | first | second | debug',
              '* [i] root | first | second | info',
            ]);
          },
        );
      });
    });

    group('custom printer', () {
      void logAll() {
        log.d('debug');
        log.i('info');
        log2.d('debug');
        log2.i('info');
        log3.d('debug');
        log3.i('info');
      }

      CustomLogPublisher<Log> customPrinter(String prefix) =>
          CustomLogFormatter(
            format: Logger.defaultFormat,
            output: (message) => buf.add('$prefix $message'),
          );

      test('initial state', () {
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isTrue);
        expect(log3.publisherLinked, isTrue);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '[d] root | first | debug',
          '[i] root | first | info',
          '[d] root | first | second | debug',
          '[i] root | first | second | info',
        ]);
      });

      test('log=custom builder', () {
        log.publisher = customPrinter('+');
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isTrue);
        expect(log3.publisherLinked, isTrue);
        logAll();
        expect(buf, [
          '+ [d] root | debug',
          '+ [i] root | info',
          '+ [d] root | first | debug',
          '+ [i] root | first | info',
          '+ [d] root | first | second | debug',
          '+ [i] root | first | second | info',
        ]);
      });

      test('log2=custom builder', () {
        log2.publisher = customPrinter('+');
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isFalse);
        expect(log3.publisherLinked, isTrue);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '+ [d] root | first | debug',
          '+ [i] root | first | info',
          '+ [d] root | first | second | debug',
          '+ [i] root | first | second | info',
        ]);
      });

      test('log3=custom builder', () {
        log3.publisher = customPrinter('+');
        expect(log.publisherLinked, isFalse);
        expect(log2.publisherLinked, isTrue);
        expect(log3.publisherLinked, isFalse);
        logAll();
        expect(buf, [
          '[d] root | debug',
          '[i] root | info',
          '[d] root | first | debug',
          '[i] root | first | info',
          '+ [d] root | first | second | debug',
          '+ [i] root | first | second | info',
        ]);
      });

      test(
        'log3=custom builder + log2=custom builder + log=custom builder',
        () {
          log3.publisher = customPrinter('*');
          log2.publisher = customPrinter('+');
          log.publisher = customPrinter('#');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isFalse);
          expect(log3.publisherLinked, isFalse);
          logAll();
          expect(buf, [
            '# [d] root | debug',
            '# [i] root | info',
            '+ [d] root | first | debug',
            '+ [i] root | first | info',
            '* [d] root | first | second | debug',
            '* [i] root | first | second | info',
          ]);
        },
      );

      group('on levels', () {
        test('log.info=custom builder', () {
          log[Levels.info].publisher = customPrinter('+');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isTrue);
          expect(log3.publisherLinked, isTrue);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '+ [i] root | info',
            '[d] root | first | debug',
            '+ [i] root | first | info',
            '[d] root | first | second | debug',
            '+ [i] root | first | second | info',
          ]);
        });

        test('log2.info=custom builder', () {
          log2[Levels.info].publisher = customPrinter('+');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isFalse);
          expect(log3.publisherLinked, isTrue);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '[i] root | info',
            '[d] root | first | debug',
            '+ [i] root | first | info',
            '[d] root | first | second | debug',
            '+ [i] root | first | second | info',
          ]);
        });

        test('log3.info=custom builder', () {
          log3[Levels.info].publisher = customPrinter('+');
          expect(log.publisherLinked, isFalse);
          expect(log2.publisherLinked, isTrue);
          expect(log3.publisherLinked, isFalse);
          logAll();
          expect(buf, [
            '[d] root | debug',
            '[i] root | info',
            '[d] root | first | debug',
            '[i] root | first | info',
            '[d] root | first | second | debug',
            '+ [i] root | first | second | info',
          ]);
        });

        test(
          'log3.info=custom builder + log2.info=custom builder + log.info=custom builder',
          () {
            log3[Levels.info].publisher = customPrinter('*');
            log2[Levels.info].publisher = customPrinter('+');
            log[Levels.info].publisher = customPrinter('#');
            expect(log.publisherLinked, isFalse);
            expect(log2.publisherLinked, isFalse);
            expect(log3.publisherLinked, isFalse);
            logAll();
            expect(buf, [
              '[d] root | debug',
              '# [i] root | info',
              '[d] root | first | debug',
              '+ [i] root | first | info',
              '[d] root | first | second | debug',
              '* [i] root | first | second | info',
            ]);
          },
        );
      });
    });
  });
}
