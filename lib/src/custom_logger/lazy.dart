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
/// See also [TypedLazy] and [LazyString].
base class Lazy {
  final Object? unresolved;
  late final Object? resolved = resolveToObject(unresolved);

  Lazy(this.unresolved);

  static Object? resolveToObject(Object? obj) =>
      obj is Object? Function() ? obj() : obj;
}

/// Base class for lazy evaluation of a typed value.
///
/// Same as [Lazy], but with subsequent conversion of `Object?` to [T]
/// using the [convert] method.
///
/// If the value already has type [T], the [convert] method will not be called!
abstract base class TypedLazy<T extends Object?> extends Lazy {
  late final T value = switch (resolved) {
    final T value => value,
    _ => convert(resolved),
  };

  TypedLazy(super.unresolved);

  T convert(Object? resolved);
}

/// Class for lazy evaluation of a string value.
///
/// Same as [Lazy], but with subsequent conversion of [Object] to [String]
/// using the [toString] method. The `null` value is returned as is.
final class LazyString extends TypedLazy<String?> {
  LazyString(super.unresolved);

  @override
  String? convert(Object? resolved) => resolved?.toString();
}

/// Class for lazy evaluation of a non-nullable string value.
///
/// Same as [LazyString], but the `null` value is returned as a fallback value.
final class LazyNonNullableString extends TypedLazy<String> {
  final String fallbackValue;

  LazyNonNullableString(super.unresolved, this.fallbackValue);

  @override
  String convert(Object? resolved) => resolved?.toString() ?? fallbackValue;
}
