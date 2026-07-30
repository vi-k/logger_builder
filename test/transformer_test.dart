import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

void main() {
  group('CustomLogger.transformer', () {
    late List<Log> published;
    late Logger logger;

    setUp(() {
      published = <Log>[];
      logger = Logger('app')
        ..level = Levels.all
        ..publisher = CustomLogPublisher(published.add);
    });

    test('is applied before the publisher', () {
      logger
        ..transformer = ((log) => Log.copy(log, message: '***'))
        ..i('secret');

      expect(published.single.message, '***');
    });

    test('null transformer (default) publishes the log as is', () {
      logger.i('hello');

      expect(published.single.message, 'hello');
    });

    test('null from transformer drops the log', () {
      logger
        ..transformer = ((log) => null)
        ..i('secret');

      expect(published, isEmpty);
    });

    test('throwing transformer drops the log and reports to the zone', () {
      final errors = <Object>[];
      runZonedGuarded(
        () {
          logger
            ..transformer = ((log) => throw StateError('bad transformer'))
            ..i('secret');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(published, isEmpty);
      expect(errors.single, isA<StateError>());
    });

    test('a sublogger created after the assignment inherits it', () {
      logger.transformer = (log) => Log.copy(log, message: '***');
      final child = logger.withAddedName('child');

      child.i('secret');

      expect(published.single.message, '***');
      expect(child.transformerLinked, isTrue);
    });

    test('an assignment on the parent propagates to linked subloggers', () {
      final child = logger.withAddedName('child');
      logger.transformer = (log) => Log.copy(log, message: '***');

      child.i('secret');

      expect(published.single.message, '***');
    });

    test('an assignment on the child detaches it from the parent', () {
      final child = logger.withAddedName('child')
        ..transformer = ((log) => Log.copy(log, message: 'child'));
      logger.transformer = (log) => Log.copy(log, message: 'parent');

      child.i('secret');
      logger.i('secret');

      expect(published, hasLength(2));
      expect(published[0].message, 'child');
      expect(published[1].message, 'parent');
      expect(child.transformerLinked, isFalse);
    });

    test('self-assignment unlinks without changing the value', () {
      final child = logger.withAddedName('child');
      child.transformer = child.transformer;
      logger.transformer = (log) => Log.copy(log, message: 'parent');

      child.i('secret');

      expect(published.single.message, 'secret');
      expect(child.transformerLinked, isFalse);
    });

    test('relink() re-inherits the parent transformer', () {
      logger.transformer = (log) => Log.copy(log, message: 'parent');
      final child = logger.withAddedName('child')
        ..transformer = ((log) => Log.copy(log, message: 'child'))
        ..relink()
        ..i('secret');

      expect(published.single.message, 'parent');
      expect(child.transformerLinked, isTrue);
    });

    test('works together with a per-level publisher', () {
      final errorsOnly = <Log>[];
      logger
        ..transformer = ((log) => Log.copy(log, message: '***'))
        ..[Levels.error].publisher = CustomLogPublisher(errorsOnly.add)
        ..i('secret')
        ..e('secret');

      expect(published.single.message, '***');
      expect(errorsOnly.single.message, '***');
    });
  });
}
