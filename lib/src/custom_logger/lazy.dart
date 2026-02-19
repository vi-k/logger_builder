/// Класс для ленивого вычисления значения.
///
/// Используется для того, чтобы не тратить ресурсы на вычисление значения,
/// которое может не понадобиться. Например, при передаче значений в логгер,
/// который в релизной сборке должен быть отключен.
///
/// Непосредственное значение передаётся напрямую, а ленивое значение через
/// фунцию:
///
/// ```dart
/// info('direct value'); // Direct value
/// info(() => expensiveOperation()); // Lazy value
/// info(expensiveOperation); // Lazy value
///
/// ...
///
/// void info(Object? message) {
///   if (isDisabled) return;
///
///   final lazyMessage = Lazy(message);
///   print(lazyMessage.resolved); // Только здесь будет сделано вычисление
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

/// Базовый класс для ленивого вычисления типизированного значения.
///
/// Тоже самое, что [Lazy], но с последующим преобразованием `Object?` в [T]
/// с помощью метода [convert].
///
/// Если значение уже имеет тип [T], метод [convert] не будет вызван.
abstract base class TypedLazy<T extends Object?> extends Lazy {
  late final T value = switch (resolved) {
    final T value => value,
    _ => convert(resolved),
  };

  TypedLazy(super.unresolved);

  T convert(Object? resolved);
}

/// Класс для ленивого вычисления строкового значения.
///
/// Тоже самое, что [Lazy], но с последующим преобразованием значения в строку.
/// Если вычисление значения в результате даёт строку, то метод [convert] не
/// будет вызван.
final class LazyString extends TypedLazy<String?> {
  LazyString(super.unresolved);

  @override
  String? convert(Object? resolved) => resolved?.toString();
}
