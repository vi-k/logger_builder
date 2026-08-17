import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

void main() {
  group('Lazy', () {
    test('resolves a closure only on first access', () {
      var calls = 0;
      final lazy = Lazy(() {
        calls++;
        return 'value';
      });

      expect(calls, 0);
      expect(lazy.resolved, 'value');
      expect(lazy.resolved, 'value');
      expect(calls, 1);
    });

    test('returns a direct value as is', () {
      expect(Lazy('value').resolved, 'value');
      expect(Lazy(null).resolved, isNull);
    });

    test('Lazy.resolved wraps an already resolved value', () {
      expect(Lazy.resolved('value').resolved, 'value');
    });

    test('resolveToObject calls a function and passes a value through', () {
      expect(Lazy.resolveToObject(() => 42), 42);
      expect(Lazy.resolveToObject(42), 42);
      expect(Lazy.resolveToObject(null), isNull);
    });
  });

  group('TypedLazy (via LazyString)', () {
    test('converts the resolved value once', () {
      var calls = 0;
      final lazy = LazyString(() {
        calls++;
        return 42;
      });

      expect(lazy.value, '42');
      expect(lazy.value, '42');
      expect(calls, 1);
    });

    test('does not convert when the type already matches', () {
      expect(LazyString('plain').value, 'plain');
    });

    // Regression: B2
    test('resolved after value returns the converted value, '
        'never the internal sentinel', () {
      final lazy = LazyString(() => 'hello');

      expect(lazy.value, 'hello');
      expect(lazy.resolved, 'hello');
      expect(lazy.resolved.toString(), isNot('<no data>'));
    });

    // Regression: B2
    test('value after resolved works and resolved stays consistent', () {
      final lazy = LazyString(() => 'hello');

      expect(lazy.resolved, 'hello');
      expect(lazy.value, 'hello');
      expect(lazy.resolved, 'hello');
    });
  });

  group('LazyString', () {
    test('null resolves to the default fallback', () {
      expect(LazyString(null).value, 'null');
    });

    test('null resolves to a custom fallback', () {
      expect(LazyString(null, 'missing').value, 'missing');
    });

    // Regression: D8
    test('the resolved constructor uses the same default fallback', () {
      expect(LazyString.resolved('x').fallbackValue, 'null');
      expect(LazyString('x').fallbackValue, 'null');
    });

    test('the resolved constructor keeps the value', () {
      final lazy = LazyString.resolved('x');

      expect(lazy.value, 'x');
      expect(lazy.resolved, 'x');
    });
  });

  group('LazyStringOrNull', () {
    test('null stays null', () {
      expect(LazyStringOrNull(null).value, isNull);
    });

    test('non-string values are converted via toString', () {
      expect(LazyStringOrNull(42).value, '42');
      expect(LazyStringOrNull(() => 42).value, '42');
    });
  });

  group('failed resolution', () {
    // Regression: L3 (project review 2026-08-17[1]) — a throwing factory was
    // not memoized: _isResolved stayed false, so every later access ran the
    // factory again. With a MultiPublisher of three formatters a
    // side-effecting factory ran three times, while the class promised the
    // source had been replaced by the result.
    test('a throwing factory runs once and rethrows on every access', () {
      var calls = 0;
      final lazy = Lazy(() {
        calls++;
        throw StateError('boom');
      });

      expect(() => lazy.resolved, throwsStateError);
      expect(() => lazy.resolved, throwsStateError);
      expect(() => lazy.resolved, throwsStateError);
      expect(calls, 1, reason: 'the factory must not run again');
    });

    test('the memoized error keeps its identity', () {
      final error = StateError('boom');
      final lazy = Lazy(() => throw error);

      expect(() => lazy.resolved, throwsA(same(error)));
      expect(() => lazy.resolved, throwsA(same(error)));
    });

    test('a throwing factory propagates through TypedLazy.value', () {
      var calls = 0;
      final lazy = LazyString(() {
        calls++;
        throw StateError('boom');
      });

      expect(() => lazy.value, throwsStateError);
      expect(() => lazy.value, throwsStateError);
      expect(calls, 1);
    });
  });
}
