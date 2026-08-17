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
/// > When the value is resolved, the source is replaced by the result. Thus,
/// > if a closure was passed as the value, all variables it captured will be
/// > freed.
///
/// > [!WARNING]
/// > Resolution is a type test, not a declaration of intent: **any** value
/// > that happens to be a zero-argument function is called. `log.i(
/// > controller.dispose)` runs `dispose` instead of logging the tear-off —
/// > and it runs it inside the publisher, which for a buffered publisher is
/// > later in time and in a different zone than the logging call. Wrap such
/// > a value (`log.i(() => controller.dispose)`) or log something else.
/// >
/// > An `async` function matches the test too, and that case is worse: it is
/// > called, `Instance of 'Future<...>'` is what gets logged, and the
/// > future's error becomes an unhandled zone error — which in a plain Dart
/// > program terminates the isolate. One mistake, two failures.
/// >
/// > Until it is resolved, a `Lazy` also keeps its closure alive together
/// > with everything the closure captured — for buffered publishers, until
/// > the batch is processed.
///
/// See also [TypedLazy], [LazyString] and [LazyStringOrNull].
base class Lazy {
  /// Holds the source (a direct value or a function) before resolution and
  /// the resolved value after it.
  Object? _slot;
  bool _isResolved;

  /// Creates a lazy value from a direct value or a function computing it.
  Lazy(Object? unresolved) : _slot = unresolved, _isResolved = false;

  /// Creates a lazy value from an already resolved value.
  Lazy.resolved(Object? resolved) : _slot = resolved, _isResolved = true;

  /// The resolved value.
  ///
  /// On first access, computes the value via [resolveToObject]; the source
  /// is replaced by the result, so a passed closure is released. Subsequent
  /// accesses return the memoized result.
  ///
  /// A throwing factory is memoized too, like `late final`: the error is
  /// stored, the closure is released, and every later access rethrows the
  /// same error with the original stack trace. Otherwise a factory with a
  /// side effect ran again on each access — three times over a
  /// `MultiPublisher` of three formatters — while the class promised the
  /// source had been replaced by the result.
  Object? get resolved {
    if (!_isResolved) {
      try {
        _slot = resolveToObject(_slot);
      } on Object catch (error, stackTrace) {
        _slot = _FailedResolution(error, stackTrace);
        _isResolved = true;
        rethrow;
      }
      _isResolved = true;
    }

    if (_slot case final _FailedResolution failure) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }

    return _slot;
  }

  /// Calls [obj] if it is a function, otherwise returns it as is.
  static Object? resolveToObject(Object? obj) =>
      obj is Object? Function() ? obj() : obj;
}

/// The memoized failure of a [Lazy] factory.
///
/// Never leaves the object: [Lazy.resolved] rethrows it instead of returning
/// it, so no sentinel is observable from outside.
final class _FailedResolution {
  final Object error;
  final StackTrace stackTrace;

  const _FailedResolution(this.error, this.stackTrace);
}

/// Base class for lazy evaluation of a typed value.
///
/// Same as [Lazy], but with subsequent conversion of `Object?` to [T]
/// using the [convert] method.
///
/// If the value already has type [T], the [convert] method will not be called!
///
/// > [!IMPORTANT]
/// > When the value is converted, the original resolved object is released:
/// > after reading [value], the [resolved] getter returns the converted
/// > [value].
abstract base class TypedLazy<T extends Object?> extends Lazy {
  bool _isConverted;

  /// Creates a lazy typed value from a direct value or a function
  /// computing it.
  TypedLazy(super.unresolved) : _isConverted = false;

  /// Creates a lazy typed value from an already resolved value of type [T].
  TypedLazy.resolved(T super.resolved) : _isConverted = true, super.resolved();

  /// The resolved value converted to [T].
  ///
  /// The conversion happens once; the original resolved object is released
  /// afterwards, and [resolved] returns the converted value from then on.
  T get value {
    if (!_isConverted) {
      final resolved = this.resolved;
      _slot = resolved is T ? resolved : convert(resolved);
      _isConverted = true;
    }

    return _slot as T;
  }

  /// Converts a [resolved] value whose type does not match [T].
  ///
  /// If the conversion is impossible, throw an exception or return
  /// a fallback value.
  T convert(Object? resolved);
}

/// Class for lazy evaluation of a string value.
///
/// Same as [Lazy], but with subsequent conversion of [Object] to [String]
/// using the [toString] method. The `null` value is returned as
/// a [fallbackValue].
final class LazyString extends TypedLazy<String> {
  /// The string returned when the resolved value is `null`.
  final String fallbackValue;

  /// Creates a lazy string from a direct value or a function computing it.
  LazyString(super.unresolved, [this.fallbackValue = 'null']);

  /// Creates a lazy string from an already resolved value.
  LazyString.resolved(super.resolved, [this.fallbackValue = 'null'])
    : super.resolved();

  @override
  String convert(Object? resolved) => resolved?.toString() ?? fallbackValue;
}

/// Class for lazy evaluation of a string value or null.
///
/// Same as [Lazy], but with subsequent conversion of [Object] to [String]
/// using the [toString] method. The `null` value is returned as is.
final class LazyStringOrNull extends TypedLazy<String?> {
  /// Creates a lazy nullable string from a direct value or a function
  /// computing it.
  LazyStringOrNull(super.unresolved);

  /// Creates a lazy nullable string from an already resolved value.
  LazyStringOrNull.resolved(super.resolved) : super.resolved();

  @override
  String? convert(Object? resolved) => resolved?.toString();
}
