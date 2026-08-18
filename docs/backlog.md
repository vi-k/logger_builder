# TODO

- Саблогеры другого типа

- По-уровневый флаг связанности паблишера. Сейчас `_publisherLinked` —
  один bool на логгер, поэтому точечное присвоение
  `child[level].publisher = X` отвязывает ребёнка **целиком**: последующее
  `parent.publisher = Y` не доходит уже ни до одного его уровня.
  Воспроизведение на 0.6.2:

  ```dart
  final parent = Logger('app')..level = Levels.all..publisher = p1;
  final child = parent.createChild(name: 'net');
  child[Levels.debug].publisher = p2;  // трогаем ОДИН уровень
  parent.publisher = p3;               // до ребёнка не доходит вовсе
  child.i('info');                     // уходит в p1, ожидался p3
  ```

  Что нужно решить, помимо самого флага:

  - Флаг переезжает на уровень (`CustomLevelLogger._publisherLinked` либо
    `Set<int>` отвязанных уровней в логгере), и вокруг него пересобираются
    `_setPublisher`, `_setLevelPublisher`, `_inheritLevelPublisher`,
    `_propagateLevelPublisher`, `_relink`.
  - Что после этого отвечает публичный `publisherLinked` — вероятно, «все
    уровни связаны»; нужны ли `child[level].publisherLinked` и
    `relink(level)`.
  - Что делает присвоение общего `publisher` логгеру: накрывает все уровни
    (в том числе отвязанные) или только связанные. От этого зависит, можно
    ли вообще вернуть уровень в связанное состояние без `relink`.
  - Идиома «отвязать, не меняя значения» (`child[level].publisher =
    child[level].publisher`) после смены семантики означает уже другое —
    её описание в `relink` и в дартдоке `CustomLevelLogger.publisher`
    придётся переписать.

  Цена: поведение задокументировано намеренно («the link flag is per
  logger, not per level» в дартдоке `CustomLevelLogger.publisher`), то есть
  это смена публичного контракта, а не починка недосмотра — ломающее,
  0.7.0. Плюс 33 обращения к `publisherLinked` в `hierarchy_test.dart` и
  `hierarchy_propagation_test.dart` фиксируют старую семантику, и по два
  места в `README.md` и `README.ru.md`.
