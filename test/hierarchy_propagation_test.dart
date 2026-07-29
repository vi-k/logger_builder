import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/variable_logger.dart';

WeakReference<VarLogger> createDiscardedSublogger(VarLogger parent) =>
    WeakReference(VarLogger.sub(parent, [Levels.info]));

/// Tries to provoke a garbage collection until [probe] is cleared.
Future<bool> tryCollectGarbage(WeakReference<Object> probe) async {
  for (var i = 0; i < 50 && probe.target != null; i++) {
    // Allocation pressure to trigger scavenges and old-space collections.
    List<Object>.generate(100000, (_) => Object(), growable: false);
    await Future<void>.delayed(Duration.zero);
  }
  return probe.target == null;
}

void main() {
  group('per-level publisher propagation', () {
    // Regression: B6
    test('skips subloggers that did not register the level', () {
      final published = <String?>[];
      final parent = VarLogger([Levels.info, Levels.error])..level = Levels.all;
      final child = VarLogger.sub(parent, [Levels.info]);

      parent[Levels.error].publisher =
          CustomLogPublisher((log) => published.add(log.message));

      expect(child.publisherLinked, isTrue);
      parent.logAt(Levels.error)('oops');
      expect(published, ['oops']);
    });

    // Regression: B6
    test('still reaches subloggers that do have the level', () {
      final published = <String?>[];
      final parent = VarLogger([Levels.info, Levels.error])..level = Levels.all;
      final childWithout = VarLogger.sub(parent, [Levels.info]);
      final childWith = VarLogger.sub(parent, [Levels.info, Levels.error]);

      parent[Levels.error].publisher =
          CustomLogPublisher((log) => published.add('parent:${log.message}'));

      expect(childWithout.publisherLinked, isTrue);
      childWith.logAt(Levels.error)('oops');
      expect(published, ['parent:oops']);
    });
  });

  group('sublogger pruning', () {
    // Regression: M1
    test('pruneSubloggers keeps live subloggers', () {
      final parent = VarLogger([Levels.info]);
      final child = VarLogger.sub(parent, [Levels.info]);

      parent.pruneSubloggers();

      expect(parent.subLoggersCount, 1);
      expect(child.levelLinked, isTrue);
    });

    // Regression: M1
    test('dead subloggers are pruned from the parent', () async {
      final parent = VarLogger([Levels.info]);
      final probe = createDiscardedSublogger(parent);
      expect(parent.subLoggersCount, 1);

      final collected = await tryCollectGarbage(probe);
      if (!collected) {
        markTestSkipped('GC did not collect the sublogger; cannot verify');
        return;
      }

      parent.pruneSubloggers();

      expect(parent.subLoggersCount, 0);
    });

    // Regression: M1
    test('level changes prune dead sublogger references', () async {
      final parent = VarLogger([Levels.info]);
      final probe = createDiscardedSublogger(parent);

      final collected = await tryCollectGarbage(probe);
      if (!collected) {
        markTestSkipped('GC did not collect the sublogger; cannot verify');
        return;
      }

      parent.level = Levels.info;

      expect(parent.subLoggersCount, 0);
    });
  });
}
