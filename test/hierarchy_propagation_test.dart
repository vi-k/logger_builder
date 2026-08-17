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

/// Overrides the public [level] and [transformer] setters with bodies that
/// touch a `late` field initialized in the constructor body — legal
/// subclassing that crashes if the setters are dispatched virtually while
/// the superclass is still constructing.
final class _SetterOverridingLogger extends VarLogger {
  final observed = <String>[];
  late final String tag;

  _SetterOverridingLogger.sub(VarLogger parent)
      : super.sub(parent, [Levels.info]) {
    tag = 'ready';
  }

  @override
  set level(int value) {
    observed.add(tag);
    super.level = value;
  }

  @override
  set transformer(LogTransformer<VarLog>? value) {
    observed.add(tag);
    super.transformer = value;
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

    // Regression: M4 (project review 2026-08-16[4]) — a level registered
    // after the publisher was assigned kept the no-op publisher while
    // reporting itself enabled, so its logs vanished without a trace.
    test('a level registered after the publisher inherits it', () {
      final published = <String?>[];
      final logger = VarLogger([Levels.info])
        ..level = Levels.all
        ..publisher = CustomLogPublisher((log) => published.add(log.message))
        ..addLevel(Levels.error)
        ..level = Levels.all;

      logger.logAt(Levels.error)('late level');

      expect(logger[Levels.error].isEnabled, isTrue);
      expect(published, ['late level']);
    });

    // Regression: M4 — relink used to walk only the parent's own levels, so
    // a level the child has and the parent lacks kept a stale publisher.
    test('relink gives the parent common publisher to extra child levels', () {
      final published = <String?>[];
      final parent = VarLogger([Levels.info])..level = Levels.all;
      final child = VarLogger.sub(parent, [Levels.info, Levels.error])
        ..level = Levels.all
        ..publisher = const CustomLogPublisher.noOp();

      parent.publisher =
          CustomLogPublisher((log) => published.add(log.message));

      expect(child.relink(), isTrue);
      child.logAt(Levels.error)('extra level');

      expect(published, ['extra level']);
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

    // Regression: M3 (project review 2026-08-16[4]) — the CR8 fix covered
    // relink() but _relink itself still went through the public, overridable
    // level and transformer setters, so the same crash was one override away.
    test('construction does not dispatch level or transformer setters', () {
      final parent = VarLogger([Levels.info]);

      late _SetterOverridingLogger child;
      expect(
        () => child = _SetterOverridingLogger.sub(parent),
        returnsNormally,
      );
      expect(child.observed, isEmpty);

      // Direct assignment still reaches the override.
      child.level = Levels.all;
      expect(child.observed, ['ready']);
    });

    // Regression: M3 — propagation from the parent must not reach subclass
    // setter overrides either, for the same reason.
    test('propagation does not dispatch subclass setter overrides', () {
      final parent = VarLogger([Levels.info]);
      final child = _SetterOverridingLogger.sub(parent);

      parent.level = Levels.all;

      expect(child.level, Levels.all);
      expect(child.observed, isEmpty);
    });
  });

  group('publisher inheritance for levels registered later', () {
    // Regression: M7 (project review 2026-08-17[1]) — the rule lived in a
    // field written only by the common `publisher =` setter, so a logger
    // configured entirely through `logger[level].publisher` had nothing
    // cached: a level registered afterwards stayed on the no-op publisher
    // while reporting isEnabled == true.
    test('a level added after only per-level publishers stays unconfigured',
        () {
      final published = <String?>[];
      final logger = VarLogger([Levels.info])..level = Levels.all;
      logger[Levels.info].publisher =
          CustomLogPublisher((log) => published.add(log.message));

      logger.addLevel(Levels.error);
      logger.logAt(Levels.error)('oops');

      // Deliberately no guessing: handing the new level the publisher chosen
      // for a *different* level would be an invention. What was wrong before
      // is that this state was undetectable.
      expect(logger[Levels.error].hasPublisher, isFalse);
      expect(logger[Levels.error].isEnabled, isTrue);
      expect(published, isEmpty);
    });

    test('a level added after a common publisher inherits it', () {
      final published = <String?>[];
      final logger = VarLogger([Levels.info])
        ..level = Levels.all
        ..publisher = CustomLogPublisher((log) => published.add(log.message))
        ..addLevel(Levels.error)
        ..level = Levels.all;

      logger.logAt(Levels.error)('oops');

      expect(logger[Levels.error].hasPublisher, isTrue);
      expect(published, ['oops']);
    });

    test('a level added on a linked child takes the parent per-level publisher',
        () {
      final common = <String?>[];
      final errorsOnly = <String?>[];
      final parent = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all
        ..publisher = CustomLogPublisher((log) => common.add(log.message));
      parent[Levels.error].publisher =
          CustomLogPublisher((log) => errorsOnly.add(log.message));

      final child = VarLogger.sub(parent, [Levels.info])
        ..addLevel(Levels.error);
      child.logAt(Levels.error)('oops');

      expect(child.publisherLinked, isTrue);
      expect(
        errorsOnly,
        ['oops'],
        reason: 'the child must not diverge from the parent for that level',
      );
      expect(common, isEmpty);
    });

    test('hasPublisher exposes a level that is enabled but goes nowhere', () {
      final logger = VarLogger([Levels.info])..level = Levels.all;

      expect(logger[Levels.info].isEnabled, isTrue);
      expect(
        logger[Levels.info].hasPublisher,
        isFalse,
        reason: 'enabled and unconfigured must be tellable apart',
      );

      logger.publisher = CustomLogPublisher((log) {});

      expect(logger[Levels.info].hasPublisher, isTrue);
    });

    test('inheriting from a parent with no publisher does not fake one', () {
      final parent = VarLogger([Levels.info]);
      final child = VarLogger.sub(parent, [Levels.info]);

      expect(child[Levels.info].hasPublisher, isFalse);
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

    // Regression: M22 (project review 2026-08-17[1]) — every existing pruning
    // test either calls pruneSubloggers() by hand or changes a setting, and
    // both prune unconditionally. That hid the amortized prune on
    // registration: raising its threshold so it never fires passed the whole
    // suite, while a parent that only ever creates short-lived subloggers —
    // the documented "sublogger per request" pattern — would accumulate dead
    // references without bound.
    test('registration alone compacts the sublogger list', () {
      const total = 2000;
      final parent = VarLogger([Levels.info])..level = Levels.all;

      for (var i = 0; i < total; i++) {
        createDiscardedSublogger(parent);
        // Allocation pressure, so the discarded subloggers become collectable
        // during the loop rather than only after it. No setting is touched
        // here on purpose: registration must carry the pruning on its own.
        List<Object>.generate(2000, (_) => Object(), growable: false);
      }

      expect(
        parent.subLoggersCount,
        lessThan(total),
        reason: 'registration must prune as it grows, not only on propagation',
      );
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
