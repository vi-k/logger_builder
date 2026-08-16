import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/variable_logger.dart';

WeakReference<VarLogger> createDiscardedSublogger(VarLogger parent) =>
    WeakReference(VarLogger.sub(parent, [Levels.info]));

/// Overrides [VarLogger.relink] with a body that touches a `late` field
/// initialized in the constructor body — a legal subclass that would crash
/// if `relink` were virtually dispatched during superclass construction.
final class _RelinkOverridingLogger extends VarLogger {
  final relinkTags = <String>[];
  late final String tag;

  _RelinkOverridingLogger.sub(VarLogger parent)
      : super.sub(parent, [Levels.info]) {
    tag = 'ready';
  }

  @override
  bool relink() {
    relinkTags.add(tag);
    return super.relink();
  }
}

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

  // Regression: D7 (0.4.0)
  group('hierarchy management API', () {
    test('levels lists the registered levels', () {
      expect(
        VarLogger([Levels.info, Levels.error]).levels,
        unorderedEquals([Levels.info, Levels.error]),
      );
    });

    test('relink re-attaches an unlinked sublogger to its parent', () {
      final parentPublished = <String?>[];
      final parent = VarLogger([Levels.info])..level = Levels.off;
      // Created linked, then immediately unlinked (level and publisher).
      final child = VarLogger.sub(parent, [Levels.info])
        ..level = Levels.all
        ..publisher = const CustomLogPublisher.noOp();
      expect(child.levelLinked, isFalse);
      expect(child.publisherLinked, isFalse);

      parent
        ..level = Levels.all
        ..publisher =
            CustomLogPublisher((log) => parentPublished.add(log.message));
      child.logAt(Levels.info)('before relink');
      expect(parentPublished, isEmpty);

      expect(child.relink(), isTrue);

      expect(child.levelLinked, isTrue);
      expect(child.publisherLinked, isTrue);
      expect(child.level, parent.level);
      child.logAt(Levels.info)('after relink');
      expect(parentPublished, ['after relink']);

      // Parent updates propagate again.
      parent.level = Levels.off;
      expect(child.level, Levels.off);
    });

    test('relink returns false for a root logger', () {
      expect(VarLogger([Levels.info]).relink(), isFalse);
    });

    // Regression: CR8 (cross-review 0.4.0)
    test('construction does not dispatch relink to subclass overrides', () {
      final parent = VarLogger([Levels.info]);

      late _RelinkOverridingLogger child;
      expect(
        () => child = _RelinkOverridingLogger.sub(parent),
        returnsNormally,
      );

      expect(child.levelLinked, isTrue);
      expect(child.relink(), isTrue);
      expect(child.relinkTags, ['ready']);
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
      expect(
        collected,
        isTrue,
        reason: 'the parent must not keep a discarded sublogger alive; '
            'skipping here would hide exactly the leak this test guards',
      );

      parent.pruneSubloggers();

      expect(parent.subLoggersCount, 0);
    });

    // Regression: M1
    test('level changes prune dead sublogger references', () async {
      final parent = VarLogger([Levels.info]);
      final probe = createDiscardedSublogger(parent);

      final collected = await tryCollectGarbage(probe);
      expect(
        collected,
        isTrue,
        reason: 'the parent must not keep a discarded sublogger alive; '
            'skipping here would hide exactly the leak this test guards',
      );

      parent.level = Levels.info;

      expect(parent.subLoggersCount, 0);
    });

    // Regression: H1 (project review 2026-08-16[4]) — the parent reference
    // used to be weak too, so an intermediate logger the user did not keep
    // was collected and its descendants silently stopped following the root
    // while still reporting themselves as linked.
    test('an unreferenced intermediate logger keeps the chain alive', () async {
      final root = VarLogger([Levels.info]);
      final leaf = VarLogger.sub(
        VarLogger.sub(root, [Levels.info]),
        [Levels.info],
      );

      root.level = Levels.all;
      expect(leaf.level, Levels.all);

      final collected = await tryCollectGarbage(WeakReference(Object()));
      expect(collected, isTrue, reason: 'the probe should force a collection');

      root.level = Levels.info;

      expect(
        leaf.level,
        Levels.info,
        reason: 'the leaf must keep following the root across a collection',
      );
      expect(root.subLoggersCount, 1);
      expect(leaf.relink(), isTrue);
    });
  });
}
