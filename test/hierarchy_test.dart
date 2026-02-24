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
      log =
          Logger('root')
            ..level = Levels.all
            ..printer = buf.add;
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

    group('builder', () {
      void logAll() {
        log.d('debug');
        log.i('info');
        log2.d('debug');
        log2.i('info');
        log3.d('debug');
        log3.i('info');
      }

      String Function(LogEntry entry) customBuilder(String prefix) =>
          (entry) => '$prefix ${Logger.defaultBuilder(entry)}';

      test('initial state', () {
        expect(log.builderLinked, isFalse);
        expect(log2.builderLinked, isTrue);
        expect(log3.builderLinked, isTrue);
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
        log.builder = customBuilder('+');
        expect(log.builderLinked, isFalse);
        expect(log2.builderLinked, isTrue);
        expect(log3.builderLinked, isTrue);
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
        log2.builder = customBuilder('+');
        expect(log.builderLinked, isFalse);
        expect(log2.builderLinked, isFalse);
        expect(log3.builderLinked, isTrue);
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
        log3.builder = customBuilder('+');
        expect(log.builderLinked, isFalse);
        expect(log2.builderLinked, isTrue);
        expect(log3.builderLinked, isFalse);
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
          log3.builder = customBuilder('*');
          log2.builder = customBuilder('+');
          log.builder = customBuilder('#');
          expect(log.builderLinked, isFalse);
          expect(log2.builderLinked, isFalse);
          expect(log3.builderLinked, isFalse);
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
          log[Levels.info].builder = customBuilder('+');
          expect(log.builderLinked, isFalse);
          expect(log2.builderLinked, isTrue);
          expect(log3.builderLinked, isTrue);
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
          log2[Levels.info].builder = customBuilder('+');
          expect(log.builderLinked, isFalse);
          expect(log2.builderLinked, isFalse);
          expect(log3.builderLinked, isTrue);
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
          log3[Levels.info].builder = customBuilder('+');
          expect(log.builderLinked, isFalse);
          expect(log2.builderLinked, isTrue);
          expect(log3.builderLinked, isFalse);
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
            log3[Levels.info].builder = customBuilder('*');
            log2[Levels.info].builder = customBuilder('+');
            log[Levels.info].builder = customBuilder('#');
            expect(log.builderLinked, isFalse);
            expect(log2.builderLinked, isFalse);
            expect(log3.builderLinked, isFalse);
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

    group('printer', () {
      void logAll() {
        log.d('debug');
        log.i('info');
        log2.d('debug');
        log2.i('info');
        log3.d('debug');
        log3.i('info');
      }

      void Function(String message) customPrinter(String prefix) =>
          (message) => buf.add('$prefix $message');

      test('initial state', () {
        expect(log.printerLinked, isFalse);
        expect(log2.printerLinked, isTrue);
        expect(log3.printerLinked, isTrue);
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
        log.printer = customPrinter('+');
        expect(log.printerLinked, isFalse);
        expect(log2.printerLinked, isTrue);
        expect(log3.printerLinked, isTrue);
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
        log2.printer = customPrinter('+');
        expect(log.printerLinked, isFalse);
        expect(log2.printerLinked, isFalse);
        expect(log3.printerLinked, isTrue);
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
        log3.printer = customPrinter('+');
        expect(log.printerLinked, isFalse);
        expect(log2.printerLinked, isTrue);
        expect(log3.printerLinked, isFalse);
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
          log3.printer = customPrinter('*');
          log2.printer = customPrinter('+');
          log.printer = customPrinter('#');
          expect(log.printerLinked, isFalse);
          expect(log2.printerLinked, isFalse);
          expect(log3.printerLinked, isFalse);
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
          log[Levels.info].printer = customPrinter('+');
          expect(log.printerLinked, isFalse);
          expect(log2.printerLinked, isTrue);
          expect(log3.printerLinked, isTrue);
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
          log2[Levels.info].printer = customPrinter('+');
          expect(log.printerLinked, isFalse);
          expect(log2.printerLinked, isFalse);
          expect(log3.printerLinked, isTrue);
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
          log3[Levels.info].printer = customPrinter('+');
          expect(log.printerLinked, isFalse);
          expect(log2.printerLinked, isTrue);
          expect(log3.printerLinked, isFalse);
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
            log3[Levels.info].printer = customPrinter('*');
            log2[Levels.info].printer = customPrinter('+');
            log[Levels.info].printer = customPrinter('#');
            expect(log.printerLinked, isFalse);
            expect(log2.printerLinked, isFalse);
            expect(log3.printerLinked, isFalse);
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
