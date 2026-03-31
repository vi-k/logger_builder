final class _NoData {
  const _NoData();

  @override
  String toString() => '<no data>';
}

const _noData = _NoData();

/// Class for lazy evaluation of a value.
///
/// Used to avoid resource consumption on value calculation, which may not be
/// needed. For example, when passing values to a logger, which should be
/// disabled in the release build.
///
/// The value is passed directly, or through a function:
///
/// ```dart
/// info('direct value'); // Direct value
/// info(() => expensiveOperation()); // Lazy value
/// info(expensiveOperation); // Lazy value
///
/// void info(Object? message) {
///   if (isDisabled) return;
///
///   final lazyMessage = Lazy(message);
///   print(lazyMessage.resolved); // Only here will the calculation be made
/// }
/// ```
///
/// > [!IMPORTANT]
/// > When the value is resolved, the unresolved value will be cleared. Thus,
/// > if a closure was passed as the value, all variables it captured will be
/// > freed.
///
/// See also [TypedLazy], [LazyString] and [LazyStringOrNull].
base class Lazy {
  Object? _unresolved;
  Object? _resolved = _noData;

  Lazy(this._unresolved);

  Lazy.resolved(Object? resolved)
      : _unresolved = _noData,
        _resolved = resolved;

  Object? get resolved {
    if (identical(_resolved, _noData)) {
      _resolved = resolveToObject(_unresolved);
      _unresolved = _noData;
    }

    return _resolved;
  }

  static Object? resolveToObject(Object? obj) =>
      obj is Object? Function() ? obj() : obj;
}

/// Base class for lazy evaluation of a typed value.
///
/// Same as [Lazy], but with subsequent conversion of `Object?` to [T]
/// using the [convert] method.
///
/// If the value already has type [T], the [convert] method will not be called!
///
/// > [!IMPORTANT]
/// > When the value is converted, the [resolved] value will be cleared.
abstract base class TypedLazy<T extends Object?> extends Lazy {
  Object? _value = _noData;

  TypedLazy(super.unresolved);

  TypedLazy.resolved(T super.resolved)
      : _value = resolved,
        super.resolved();

  T get value {
    if (identical(_value, _noData)) {
      final resolved = this.resolved;
      final value = resolved is T ? resolved : convert(resolved);
      _resolved = _noData;
      _value = value;
      return value;
    }

    return _value as T;
  }

  T convert(Object? resolved);
}

/// Class for lazy evaluation of a string value.
///
/// Same as [Lazy], but with subsequent conversion of [Object] to [String]
/// using the [toString] method. The `null` value is returned as
/// a [fallbackValue].
final class LazyString extends TypedLazy<String> {
  final String fallbackValue;

  LazyString(super.unresolved, [this.fallbackValue = 'null']);

  LazyString.resolved(super.resolved)
      : fallbackValue = '',
        super.resolved();

  @override
  String convert(Object? resolved) => resolved?.toString() ?? fallbackValue;
}

/// Class for lazy evaluation of a string value or null.
///
/// Same as [Lazy], but with subsequent conversion of [Object] to [String]
/// using the [toString] method. The `null` value is returned as is.
final class LazyStringOrNull extends TypedLazy<String?> {
  LazyStringOrNull(super.unresolved);

  LazyStringOrNull.resolved(super.resolved) : super.resolved();

  @override
  String? convert(Object? resolved) => resolved?.toString();
}
