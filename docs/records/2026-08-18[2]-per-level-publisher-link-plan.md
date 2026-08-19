> **Состояние на 2026-08-19:** выполнен целиком, все четыре задачи
> закрыты (`5d25516`, `020206f`, `dd780dc`, `a0db6f3`, `964e627`);
> находки ревью закрыты сверх плана (`fcd7098`, `3d512aa`, `956e0d7`,
> `3de3424`).
> **Что это:** план работ по пер-уровневому пину паблишера — четыре
> задачи с TDD-шагами, кодом и проверками.
> **Связанные записи:** `2026-08-18[1]-per-level-publisher-link-design.md`
> (дизайн, который этот план исполняет),
> `2026-08-19[1]-per-level-publisher-link-report.md` (отчёт волны).

# Пер-уровневый пин паблишера: план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Цель:** точечное `logger[level].publisher = X` перестаёт отвязывать
логгер от родителя целиком; отвязанным становится один уровень, и его
можно вернуть обратно.

**Устройство:** флагов два. Пин (`_hasOwnPublisher`) живёт на уровне и
ставится только точечным присвоением; связь (`_publisherLinked`) остаётся
на логгере и гасится только общим сеттером. Маркером обхода, который
ломает циклы в графе саблоггеров, на обоих путях служит связь логгера —
пин им быть не может, потому что логгер вправе не иметь уровня, которым
идёт распространение.

**Инструменты:** Dart, пакет `test`, `dart analyze`, `dart format`.

**Дизайн:** `docs/records/2026-08-18[1]-per-level-publisher-link-design.md`
— читать вместе с этим планом; расхождение между ними решается в пользу
дизайна.

## Общие ограничения

- Версия — 0.7.0, ломающая. Порог SDK не трогать: `^3.6.0`, `meta`
  `^1.15.0`.
- Строки — не длиннее 80 колонок, включая dartdoc и markdown.
- `require_trailing_commas` включён: запятая после последнего аргумента
  в многострочных вызовах обязательна.
- По-английски: dartdoc в `lib/`, `README.md`, `CHANGELOG.md`, сообщения
  коммитов. По-русски: `docs/*.md`.
- Правишь `README.md` — правь `README.ru.md` **тем же коммитом**
  (`AGENTS.md` §2).
- Перед тем как назвать задачу законченной: `dart analyze` (из корня,
  захватывает `example/`), `dart test`, `dart format --output=none
  --set-exit-if-changed .` — привести вывод.
- Каждая кодовая правка проверяется мутацией: временно откатить правку,
  убедиться, что падает именно новый тест, вернуть.
- Публикация в связку задач **не входит** и не выполняется: ни релизного
  коммита, ни тега, ни `dart pub publish` (`AGENTS.md` §5).

---

### Задача 1: пин на уровне, точечное присвоение не рвёт связь

Ядро починки. После неё репродукция из бэклога зелёная.

**Файлы:**
- Изменить: `lib/src/custom_logger/custom_level_logger.dart` (поле,
  геттер, `_resetPublisher`)
- Изменить: `lib/src/custom_logger/custom_logger.dart:456-486`
  (`_setLevelPublisher`, `_inheritLevelPublisher`,
  `_propagateLevelPublisher`)
- Тесты: `test/hierarchy_propagation_test.dart`, `test/hierarchy_test.dart`

**Интерфейсы:**
- Даёт дальше: `CustomLevelLogger.hasOwnPublisher` (`bool`, `true` —
  уровень держит свой паблишер); приватные `_hasOwnPublisher` (`bool`,
  поле уровня) и `_resetPublisher()` (`void`, возвращает уровень на no-op
  и ставит `_hasPublisher = false`).

- [ ] **Шаг 1: написать падающий тест — репродукция из бэклога**

В `test/hierarchy_propagation_test.dart`, в группу
`per-level publisher propagation`:

```dart
    // Regression: a per-level assignment used to clear the link flag of
    // the whole logger, so the parent's next common publisher reached
    // none of the child's levels.
    test('a per-level assignment keeps the other levels following', () {
      final published = <String?>[];
      final parent = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all
        ..publisher = const CustomLogPublisher.noOp();
      final child = VarLogger.sub(parent, [Levels.info, Levels.error]);

      child[Levels.error].publisher = const CustomLogPublisher.noOp();
      parent.publisher =
          CustomLogPublisher((log) => published.add(log.message));
      child.logAt(Levels.info)('info');

      expect(published, ['info']);
      expect(child.publisherLinked, isTrue);
      expect(child[Levels.error].hasOwnPublisher, isTrue);
      expect(child[Levels.info].hasOwnPublisher, isFalse);
    });
```

- [ ] **Шаг 2: убедиться, что тест падает**

Запустить:

```sh
dart test test/hierarchy_propagation_test.dart \
  -n 'a per-level assignment keeps'
```

Ожидается: ошибка компиляции — `hasOwnPublisher` не определён.

- [ ] **Шаг 3: завести поле и геттер на уровне**

В `lib/src/custom_logger/custom_level_logger.dart`, рядом с
`_hasPublisher`:

```dart
  /// Whether this level holds a publisher of its own.
  ///
  /// Set by `logger[level].publisher = ...` and cleared by [relink]. A
  /// level that holds its own publisher takes nothing from above: neither
  /// a parent update nor its own logger's common `publisher` setter
  /// overrules it, so the order of the two assignments stops mattering.
  ///
  /// Different question from [hasPublisher], which asks whether the
  /// publisher is a real one rather than the no-op default: an inherited
  /// publisher is real but not its own.
  bool _hasOwnPublisher = false;
```

и геттер рядом с `hasPublisher`:

```dart
  /// Whether this level holds a publisher of its own rather than one taken
  /// from above.
  ///
  /// `true` after `logger[level].publisher = ...`; [relink] turns it back
  /// to `false`. See [hasPublisher] for the other question — whether the
  /// publisher goes anywhere at all.
  bool get hasOwnPublisher => _hasOwnPublisher;
```

- [ ] **Шаг 4: переписать три метода распространения**

В `lib/src/custom_logger/custom_logger.dart` заменить
`_setLevelPublisher`, `_inheritLevelPublisher` и
`_propagateLevelPublisher` на:

```dart
  // A direct per-level assignment pins the level and leaves this logger's
  // link to its parent alone: pinning one level must not stop the others
  // from following the parent.
  void _setLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    this[level]
      .._setPublisher(publisher)
      .._hasOwnPublisher = true;
    _propagateLevelPublisher(level, publisher);
  }

  /// Same as [_setLevelPublisher], but arriving from the parent: the level
  /// takes the value without pinning, and this logger is silently skipped
  /// when it did not register [level] — a sublogger is not required to
  /// have all the levels of its parent.
  ///
  /// A pinned level stops the descent here: it does not change, so nothing
  /// below it inherits a change either.
  void _inheritLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    if (_levelLoggers[level] case final levelLogger?) {
      if (levelLogger._hasOwnPublisher) {
        return;
      }
      levelLogger._setPublisher(publisher);
    }
    _propagateLevelPublisher(level, publisher);
  }

  // The link flag is cleared before recursing and restored after, which
  // also breaks cycles in the sublogger graph — see the note on
  // [_setLevel]. It stays the marker on this path too: the pin cannot
  // serve, because a logger that did not register [level] has no pin to
  // raise and a cycle through it would recurse until the stack is gone.
  void _propagateLevelPublisher(int level, CustomLogPublisher<Log> publisher) {
    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          .._publisherLinked = false
          .._inheritLevelPublisher(level, publisher)
          .._publisherLinked = true;
      }
    }
  }
```

- [ ] **Шаг 5: прогнать тесты, увидеть новый зелёным и старые красными**

Запустить: `dart test`

Ожидается: новый тест проходит; падают ровно те проверки, которые
фиксировали чинимое поведение —
`test/hierarchy_test.dart:369` (`log.info=custom builder`),
`:385` (`log2.info=custom builder`), `:401` (`log3.info=custom builder`)
и их близнецы во второй форме паблишера. Если падает что-то ещё — это
регресс, а не ожидаемое: разобраться до правки тестов.

- [ ] **Шаг 6: привести старые проверки к новому контракту**

В `test/hierarchy_test.dart`, группа `on levels`: там, где точечное
присвоение делали саблоггеру, связь логгера теперь остаётся поднятой,
а пин виден на уровне. Например в `log2.info=custom builder`:

```dart
            log2[Levels.info].publisher = makePublisher('+');
            expect(log.publisherLinked, isFalse);
            expect(log2.publisherLinked, isTrue);
            expect(log2[Levels.info].hasOwnPublisher, isTrue);
            expect(log3.publisherLinked, isTrue);
```

Ожидаемые строки в `buf` не трогать: распространение вниз работает
по-прежнему. `log.publisherLinked` у корня остаётся `isFalse` — у корня
нет родителя, за которым можно следовать, это не менялось.

- [ ] **Шаг 7: добавить тест цикла через логгер без этого уровня**

В группу `cycles in the sublogger graph`:

```dart
    // The pin cannot be the in-progress marker: `a` and `b` do not
    // register the level being propagated, so neither has a pin to raise.
    test('per-level propagation terminates on a cycle without the level',
        () {
      final root = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all;
      final a = VarLogger.sub(root, [Levels.info]);
      VarLogger.sub(a, [Levels.info]).attach(a);

      expect(
        () => root[Levels.error].publisher = const CustomLogPublisher.noOp(),
        returnsNormally,
      );
    });
```

- [ ] **Шаг 8: прогнать всё и проверить мутацией**

Запустить: `dart test`, затем `dart analyze` и
`dart format --output=none --set-exit-if-changed .`

Мутация: временно вернуть в `_setLevelPublisher` строку
`_publisherLinked = false;` — падать должен тест из шага 1. Вернуть как
было.

- [ ] **Шаг 9: коммит**

```bash
git add lib/src/custom_logger/ test/hierarchy_propagation_test.dart \
        test/hierarchy_test.dart
git commit -m "feat!: pin the publisher per level, not per logger"
```

---

### Задача 2: общий сеттер уважает пины

**Файлы:**
- Изменить: `lib/src/custom_logger/custom_logger.dart:334-352`
  (`_setPublisher`, новый `_inheritPublisher`, новый
  `_propagatePublisher`)
- Тесты: `test/hierarchy_propagation_test.dart`

**Интерфейсы:**
- Потребляет из задачи 1: `_hasOwnPublisher` на уровне.
- Даёт дальше: приватные `_inheritPublisher(Logger parent,
  CustomLogPublisher<Log> publisher)` и
  `_propagatePublisher(CustomLogPublisher<Log> publisher)`.

- [ ] **Шаг 1: написать падающие тесты**

В `test/hierarchy_propagation_test.dart`, новая группа:

```dart
  group('common publisher against pins', () {
    test('a pinned level survives its own logger common setter', () {
      final pinned = <String?>[];
      final common = <String?>[];
      final logger = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all;

      logger[Levels.error].publisher =
          CustomLogPublisher((log) => pinned.add(log.message));
      logger.publisher = CustomLogPublisher((log) => common.add(log.message));

      logger.logAt(Levels.error)('pinned');
      logger.logAt(Levels.info)('common');

      expect(pinned, ['pinned']);
      expect(common, ['common']);
    });

    test('assigning the common publisher twice covers everything again',
        () {
      final first = <String?>[];
      final second = <String?>[];
      final logger = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all
        ..publisher = CustomLogPublisher((log) => first.add(log.message))
        ..publisher = CustomLogPublisher((log) => second.add(log.message));

      logger.logAt(Levels.info)('info');
      logger.logAt(Levels.error)('error');

      expect(first, isEmpty);
      expect(second, ['info', 'error']);
    });

    test('the common publisher is recorded even when it covers nothing',
        () {
      final common = <String?>[];
      final logger = VarLogger([Levels.info])..level = Levels.all;

      logger[Levels.info].publisher = const CustomLogPublisher.noOp();
      logger.publisher = CustomLogPublisher((log) => common.add(log.message));
      logger
        ..addLevel(Levels.error)
        ..level = Levels.all;

      logger.logAt(Levels.error)('late level');

      expect(logger[Levels.error].hasOwnPublisher, isFalse);
      expect(common, ['late level']);
    });

    test('a mixed child does not hand the new publisher below its pin', () {
      final pinned = <String?>[];
      final fresh = <String?>[];
      final root = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all
        ..publisher = const CustomLogPublisher.noOp();
      final a = VarLogger.sub(root, [Levels.info, Levels.error]);
      final b = VarLogger.sub(a, [Levels.info, Levels.error]);

      a[Levels.error].publisher =
          CustomLogPublisher((log) => pinned.add(log.message));
      root.publisher = CustomLogPublisher((log) => fresh.add(log.message));

      b.logAt(Levels.error)('below the pin');
      b.logAt(Levels.info)('below the link');

      expect(pinned, ['below the pin']);
      expect(fresh, ['below the link']);
    });
  });
```

- [ ] **Шаг 2: убедиться, что тесты падают**

Запустить:

```sh
dart test test/hierarchy_propagation_test.dart \
  -n 'common publisher against pins'
```

Ожидается: падают первый и четвёртый (общий сеттер накрывает пин;
ребёнок раздаёт новое значение под пином). Второй и третий зелёные уже
сейчас: это регрессы на модель — повторное присвоение и запись кэша
«последний общий» — и остаться они должны зелёными.

- [ ] **Шаг 3: переписать `_setPublisher` и завести наследование**

В `lib/src/custom_logger/custom_logger.dart`:

```dart
  // The flag is cleared before recursing and restored after, which also
  // breaks cycles in the sublogger graph — see the note on [_setLevel].
  void _setPublisher(CustomLogPublisher<Log> publisher) {
    _publisherLinked = false;
    _defaultPublisher = publisher;

    for (final levelLogger in _levelLoggers.values) {
      // A pinned level holds its own publisher; its own logger does not
      // overrule it either, so the order of the two assignments stops
      // mattering.
      if (!levelLogger._hasOwnPublisher) {
        levelLogger._setPublisher(publisher);
      }
    }

    _propagatePublisher(publisher);
  }

  /// The common publisher of [parent], arriving from above.
  ///
  /// Not [_setPublisher]: a level here follows the parent's value *for
  /// that level*, which is [publisher] only where the parent holds no pin
  /// of its own. Handing [publisher] to every level would overwrite what a
  /// pinned level of the parent still publishes into.
  void _inheritPublisher(Logger parent, CustomLogPublisher<Log> publisher) {
    _defaultPublisher = publisher;

    for (final levelLogger in _levelLoggers.values) {
      if (levelLogger._hasOwnPublisher) {
        continue;
      }
      levelLogger._setPublisher(
        parent._assignedPublisherFor(levelLogger.level) ?? publisher,
      );
    }

    _propagatePublisher(publisher);
  }

  void _propagatePublisher(CustomLogPublisher<Log> publisher) {
    pruneSubloggers();
    for (final sublogger in _subloggers) {
      if (sublogger.target case final sublogger?
          when sublogger._publisherLinked) {
        sublogger
          .._publisherLinked = false
          .._inheritPublisher(this as Logger, publisher)
          .._publisherLinked = true;
      }
    }
  }
```

- [ ] **Шаг 4: прогнать тесты**

Запустить: `dart test`

Ожидается: все три новых зелёные, старые не тронуты. Особое внимание
тесту `relink gives the parent common publisher to extra child levels` —
он ходит тем же путём.

- [ ] **Шаг 5: проверить мутацией**

Убрать условие `if (!levelLogger._hasOwnPublisher)` в `_setPublisher` —
падает первый тест шага 1. Заменить в `_inheritPublisher` выражение
`parent._assignedPublisherFor(levelLogger.level) ?? publisher` на
`publisher` — падает третий. Вернуть оба.

- [ ] **Шаг 6: коммит**

```bash
git add lib/src/custom_logger/custom_logger.dart \
        test/hierarchy_propagation_test.dart
git commit -m "feat!: let a pinned level outrank the common publisher"
```

---

### Задача 3: возврат уровня под цепочку

**Файлы:**
- Изменить: `lib/src/custom_logger/custom_level_logger.dart` (публичный
  `relink`, `_resetPublisher`)
- Изменить: `lib/src/custom_logger/custom_logger.dart` (`_relinkLevel`,
  `_relink`)
- Тесты: `test/hierarchy_propagation_test.dart`

**Интерфейсы:**
- Потребляет из задач 1–2: `_hasOwnPublisher`, `_inheritLevelPublisher`,
  `_propagateLevelPublisher`.
- Даёт дальше: `CustomLevelLogger.relink()` (`void`), приватный
  `CustomLogger._relinkLevel(int level)` (`void`).

- [ ] **Шаг 1: написать падающие тесты**

```dart
  group('per-level relink', () {
    test('a relinked level follows the parent again', () {
      final parentPublished = <String?>[];
      final parent = VarLogger([Levels.info])..level = Levels.all;
      final child = VarLogger.sub(parent, [Levels.info]);

      child[Levels.info].publisher = const CustomLogPublisher.noOp();
      parent.publisher =
          CustomLogPublisher((log) => parentPublished.add(log.message));
      child.logAt(Levels.info)('while pinned');

      child[Levels.info].relink();
      child.logAt(Levels.info)('after relink');

      expect(child[Levels.info].hasOwnPublisher, isFalse);
      expect(parentPublished, ['after relink']);
    });

    test('a root level returns under its own common publisher', () {
      final common = <String?>[];
      final root = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all;

      root[Levels.info].publisher = const CustomLogPublisher.noOp();
      root.publisher = CustomLogPublisher((log) => common.add(log.message));
      root.logAt(Levels.info)('while pinned');

      root[Levels.info].relink();
      root.logAt(Levels.info)('after relink');

      expect(common, ['after relink']);
    });

    test('a level with nothing above it goes back to no publisher', () {
      final root = VarLogger([Levels.info])..level = Levels.all;

      root[Levels.info].publisher = const CustomLogPublisher.noOp();
      expect(root[Levels.info].hasPublisher, isTrue);

      root[Levels.info].relink();

      expect(root[Levels.info].hasOwnPublisher, isFalse);
      expect(root[Levels.info].hasPublisher, isFalse);
      expect(root[Levels.info].isEnabled, isTrue);
    });

    test('relink on the logger drops every pin', () {
      final parentPublished = <String?>[];
      final parent = VarLogger([Levels.info, Levels.error])
        ..level = Levels.all;
      final child = VarLogger.sub(parent, [Levels.info, Levels.error]);

      child[Levels.error].publisher = const CustomLogPublisher.noOp();
      parent.publisher =
          CustomLogPublisher((log) => parentPublished.add(log.message));

      expect(child.relink(), isTrue);
      child.logAt(Levels.error)('after relink');

      expect(child[Levels.error].hasOwnPublisher, isFalse);
      expect(parentPublished, ['after relink']);
    });
  });
```

- [ ] **Шаг 2: убедиться, что тесты падают**

Запустить:

```sh
dart test test/hierarchy_propagation_test.dart \
  -n 'per-level relink'
```

Ожидается: ошибка компиляции — у `CustomLevelLogger` нет `relink`.

- [ ] **Шаг 3: добавить сброс на уровне**

В `lib/src/custom_logger/custom_level_logger.dart`, рядом с
`_setPublisher`:

```dart
  void _resetPublisher() {
    _publisher = const CustomLogPublisher.noOp();
    _hasPublisher = false;
  }
```

и публичный метод рядом с сеттером `publisher`:

```dart
  /// Drops the publisher this level holds of its own and takes what the
  /// chain offers again: the parent's publisher for exactly this level,
  /// then the last common publisher assigned anywhere up the chain.
  ///
  /// When there is nothing to take — a root logger that was only ever
  /// configured per level — this level goes back to the no-op publisher
  /// and [hasPublisher] becomes `false`. Handing it the publisher chosen
  /// for some *other* level would be an invention.
  ///
  /// Returns nothing, unlike [CustomLogger.relink]: that one answers
  /// `false` when there is no parent to follow, while a level always has
  /// something above it — at worst its own logger.
  void relink() => logger._relinkLevel(level);
```

- [ ] **Шаг 4: реализовать `_relinkLevel` и снять пины в `_relink`**

В `lib/src/custom_logger/custom_logger.dart`:

```dart
  void _relinkLevel(int level) {
    final levelLogger = this[level];
    if (!levelLogger._hasOwnPublisher) {
      return;
    }

    levelLogger._hasOwnPublisher = false;
    final inherited = _publisherFor(level);
    if (inherited != null) {
      levelLogger._setPublisher(inherited);
    } else {
      levelLogger._resetPublisher();
    }

    _propagateLevelPublisher(level, levelLogger._publisher);
  }
```

и в `_relink`, перед тем как наследовать паблишеры от родителя:

```dart
    // A full relink drops every pin: the logger goes back to following
    // its parent in whole, levels included.
    for (final levelLogger in _levelLoggers.values) {
      levelLogger._hasOwnPublisher = false;
    }
```

- [ ] **Шаг 5: прогнать тесты**

Запустить: `dart test`

Ожидается: 4 новых теста зелёные, остальные не тронуты.

- [ ] **Шаг 6: проверить мутацией**

Убрать `levelLogger._hasOwnPublisher = false;` из `_relinkLevel` — падает
первый тест шага 1. Заменить ветку `_resetPublisher()` на пустую — падает
третий. Убрать снятие пинов из `_relink` — падает четвёртый. Вернуть всё.

- [ ] **Шаг 7: коммит**

```bash
git add lib/src/custom_logger/ test/hierarchy_propagation_test.dart
git commit -m "feat: let a single level relink to the chain"
```

---

### Задача 4: документация и версия

Кода не трогает. Отдельной задачей, потому что правки публичного текста
проверяются глазами, а не тестами.

**Файлы:**
- Изменить: `lib/src/custom_logger/custom_level_logger.dart` (дартдок
  сеттера `publisher`)
- Изменить: `lib/src/custom_logger/custom_logger.dart` (дартдок
  `publisher`, `publisherLinked`, `relink`)
- Изменить: `README.md:1035-1070` и `README.ru.md:1055-1090`
- Изменить: `docs/architecture.md` §7
- Изменить: `CHANGELOG.md`, `pubspec.yaml`

- [ ] **Шаг 1: переписать дартдок сеттера уровня**

В `custom_level_logger.dart` заменить абзац «Assigning here also detaches
the whole logger from its parent's publishers — the link flag is per
logger, not per level» на:

```dart
  /// Assigning here pins this level: it keeps this publisher until
  /// [relink] is called, and neither a parent update nor this logger's own
  /// common [CustomLogger.publisher] setter overrules it. The other levels
  /// keep following the parent, and [CustomLogger.publisherLinked] stays
  /// up — the pin is per level, the link is per logger.
```

- [ ] **Шаг 2: поправить дартдок общего сеттера и `publisherLinked`**

В `custom_logger.dart` заменить первые два абзаца дартдока сеттера
`publisher` на:

```dart
  /// Assigns a common [CustomLogPublisher] to every registered log level
  /// that does not hold a publisher of its own.
  ///
  /// A level pinned through `logger[level].publisher` keeps what it was
  /// given: its own logger does not overrule it either, so the order of
  /// the two assignments no longer matters.
  /// [CustomLevelLogger.relink] puts a pinned level back under this
  /// setter.
```

Третий абзац («Propagates the publisher change to linked subloggers…»)
оставить как есть.

К дартдоку `publisherLinked` дописать абзац:

```dart
  /// Only the common [publisher] setter drops this link. Pinning a single
  /// level through `logger[level].publisher` leaves it up — that question
  /// belongs to the level: [CustomLevelLogger.hasOwnPublisher].
```

В дартдоке `relink` заменить перечисление идиом отвязывания на:

```dart
  /// A sublogger detaches implicitly when its [level], [publisher] or
  /// [transformer] is assigned directly (`child.level = child.level` and
  /// `child.transformer = child.transformer` are the idioms to unlink
  /// without changing the value); this method is the reverse operation,
  /// and it also drops every per-level pin. To put a single level back
  /// under the chain, use [CustomLevelLogger.relink].
```

- [ ] **Шаг 3: переписать раздел README про связи**

В `README.md` (около строки 1049) заменить идиому отвязывания на
пер-уровневую и добавить возврат:

```markdown
Assigning the same value is the idiom for unlinking without changing
anything: `child.level = child.level` and `child.transformer =
child.transformer`. Publishers work per level instead: `child[Levels.info]
.publisher = X` pins that one level — the others keep following the
parent — and `child[Levels.info].relink()` puts it back under the chain.
There is no idiom for detaching every publisher at once without changing
values; assign a common publisher, or loop over `levels`.
```

- [ ] **Шаг 4: перевести правку в `README.ru.md`**

Тот же абзац по-русски, в том же месте — **этим же коммитом**. Не смог
внести — сказать владельцу в том же ответе (`AGENTS.md` §2).

- [ ] **Шаг 5: поправить инвариант в `architecture.md` §7**

Дописать к разделу про маркеры обхода:

```markdown
Пин уровня (`CustomLevelLogger.hasOwnPublisher`) маркером обхода
не служит и служить не может: логгер вправе не регистрировать уровень,
которым идёт распространение, — пина у него тогда нет вовсе, и цикл
через такой логгер остался бы без защиты. На обоих путях
распространения паблишера маркером остаётся связь логгера
(`_publisherLinked`), а пин обрывает спуск по смыслу: запиненный
уровень не меняется сам и не пропускает изменение ниже.
```

- [ ] **Шаг 6: CHANGELOG и версия**

В `pubspec.yaml` — `version: 0.7.0`. В `CHANGELOG.md` сверху:

```markdown
## 0.7.0 (unreleased)

### Breaking

- `logger[level].publisher = ...` no longer detaches the whole logger
  from its parent. It pins that one level; the others keep following the
  parent, and `publisherLinked` stays up.
- The common `logger.publisher = ...` setter no longer overwrites a
  pinned level. This applies to a lone logger as well as a sublogger, so
  the order of a common assignment and its per-level exceptions no
  longer matters.
- `publisherLinked` therefore reports `true` in cases where it used to
  report `false` — the getter itself is unchanged, the rule that clears
  it is.
- The idiom for unlinking without changing a value is per level now
  (`child[level].publisher = child[level].publisher`), and there is no
  idiom left for detaching every publisher at once: assign a common
  publisher, or loop over `levels`.
- `CustomLevelLogger` gains `hasOwnPublisher` and `relink()`. A subclass
  that already declares a member of either name stops compiling.

### Added

- `CustomLevelLogger.hasOwnPublisher` tells a pinned level from one that
  takes its publisher from above — next to `hasPublisher`, which tells a
  real publisher from the no-op one.
- `CustomLevelLogger.relink()` drops the pin and takes from the chain
  again. Unlike `CustomLogger.relink()`, it works on a root logger too:
  the level returns under that logger's common publisher.
```

- [ ] **Шаг 7: прогнать проверки целиком**

Запустить: `dart analyze`, `dart test`, `dart format --output=none
--set-exit-if-changed .`, `dart doc` (0 предупреждений и 0 ошибок).

- [ ] **Шаг 8: коммит**

```bash
git add lib/ README.md README.ru.md docs/architecture.md \
        CHANGELOG.md pubspec.yaml
git commit -m "docs: describe the per-level publisher pin"
```

---

## После плана

Работа заканчивается на подготовленном дереве версии 0.7.0. Связка
«релизный коммит — тег — публикация» в план не входит и запускается
только отдельным запросом владельца (`AGENTS.md` §5).
