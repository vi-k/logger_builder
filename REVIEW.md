# Ревью кода `logger_builder` v0.3.2

- **Дата:** 2026-07-29
- **Коммит:** `3256f42` (fix MultiPublisher: isolate publisher errors, add onError)
- **Объём:** `lib/` — 12 файлов (~1100 строк), `test/` — 707 строк
- **Базовое состояние:** `dart analyze lib test` — 0 issues; `dart test` — 32/32 зелёные.
  В `example/` — 44 info-замечания анализатора (вне рамок ревью).
- **Связанный документ:** [SPEC.md](SPEC.md) — техзадание на доработки по итогам этого ревью.
  Нумерация находок (B/M/D/T) единая в обоих документах.

## Шкала серьёзности

| Уровень | Определение |
|---|---|
| **Critical** | Потеря данных, зависание или падение процесса при штатном использовании публичного API |
| **High** | Некорректное поведение публичного API в реалистичных сценариях |
| **Medium** | Некорректность в краевых случаях, дыры в контрактах, риски для будущих фич |
| **Low** | Стиль, консистентность, документация, гигиена |

## 1. Сводная таблица

| ID | Серьёзность | Файл:строка | Кратко |
|---|---|---|---|
| B1 | Critical | `async_publisher_with_buffer.dart:51`, `..._and_param.dart:55` | `flush()` зависает навсегда на простаивающем паблишере |
| B5 | Critical | `async_publisher.dart:62-64` и 3 др. | Ошибка в `handle` → uncaught error, потеря `retryBuffer`, зависший flush |
| B2 | High | `lazy.dart:78-88` | `.resolved` после `.value` возвращает приватный сентинел `_NoData` |
| B3 | High | `async_publisher.dart:126` и 3 др. | `switch` по `FutureOr` отдаёт в `output` неожиданный `Future` при `Out = Object?` |
| B4 | High | `async_publisher_with_buffer.dart:157-166` | `remainingLogs` вычисляется до завершения async `format` |
| M1 | High | `custom_logger.dart:32-34,184` | `Finalizer` строго удерживает родителя через живых саблогеров |
| B6 | Medium | `custom_logger.dart:163-175` | `_setLevelPublisher` рвёт пропагацию `StateError`-ом посреди иерархии |
| B7 | Medium | `custom_level_logger.dart:62-63` | `name[0]`: `RangeError` в release при пустом имени, ломает не-BMP символы |
| B8 | Medium | `multi_publisher.dart:70-72` | Ошибки `flush` минуют `onError` — асимметрия с `publish` |
| B9 | Medium | `async_publisher.dart:51-60` | `flush()` после `close()` воскрешает паблишер; `publish` после close в буферном варианте молчит |
| M2 | Medium | 4 места `_listen` | `StreamSubscription` не хранятся и не отменяются |
| D3 | Medium | `..._with_param.dart:28`, `..._buffer_and_param.dart:34` | Param-паблишеры не реализуют `CustomLogPublisher`; `close()` нет ни в одном интерфейсе |
| D5 | Medium | `multi_publisher.dart:52-53` | Список паблишеров хранится по ссылке, без копии |
| T1 | Medium | `test/` | Ноль тестов на async-семейство, `lazy.dart`, Finalizer, StateError-пути |
| M3 | Low | `custom_log.dart:28` | `CustomLog.zone` не используется библиотекой, но удерживает зону |
| D1 | Low | `lib/logger_builder.dart:5-13` | Barrel экспортирует всё, включая `@visibleForTesting`-члены и недокументированный `HasFlush` |
| D2 | Low | `custom_level_logger.dart:15` | `CustomLevelLogger` — единственный класс без модификатора `base`/`final` |
| D4 | Low | `..._with_param.dart:72`, `..._buffer_and_param.dart:100` | `_AsyncParamPublisher` и `_handleData`/`_next` продублированы дословно |
| D6 | Low | `async_publisher.dart:3` и др. | Смешанные стили импортов, включая self-import barrel-файла |
| D7 | Low | `custom_logger.dart` | Нет API перечисления уровней/relink; идиома unlink недокументирована |
| D8 | Low | `lazy.dart:101,103-105` | `LazyString.resolved`: fallback `''` против `'null'` у основного конструктора |
| T2 | Low | `analysis_options.yaml`, `lib/` | Много недокументированных публичных членов; `public_member_api_docs` выключен |
| T3 | Low | `CHANGELOG.md` и др. | Нет записи про async-паблишеры; мёртвый конфиг; закомментированный код |

## 2. Ошибки корректности

### B1 (Critical). `flush()` буферных паблишеров зависает на простое

`lib/src/async_publishers/async_publisher_with_buffer.dart:51-54`, `lib/src/async_publishers/async_publisher_with_buffer_and_param.dart:55-58`.

`flush()` только создаёт `_flushCompleter` и возвращает его future. Комплитер завершается
исключительно в `_next` (`:77-84`), а `_next` вызывается только как обработчик тика из
контроллера. Тик же добавляется только в `publish` (`:42-48`) и только когда буфер был пуст.
Если к моменту вызова `flush()` очередь пуста (ничего не публиковалось или всё уже
обработано), тика не будет никогда — future не завершится никогда.

```dart
final publisher = AsyncPublisherWithBuffer<Log>((logs, retry) async { /* ... */ });
await publisher.flush(); // зависает навсегда
```

То же самое после полного опустошения очереди: `publish(...)` → обработка завершилась →
`flush()` → зависание. Достижимо и косвенно через `MultiPublisher.flush()`
(`multi_publisher.dart:70-72`), если среди детей есть простаивающий буферный паблишер —
тогда зависает и общий `flush`.

### B5 (Critical). Ошибки в `handle` не перехватываются

`lib/src/async_publishers/async_publisher.dart:62-64`, `async_publisher_with_param.dart:55-57`,
`async_publisher_with_buffer.dart:36`, `async_publisher_with_buffer_and_param.dart:43`.

Во всех четырёх базовых классах подписка создаётся как
`_controller.stream.asyncMap(...).listen(...)` — без `onError`. Исключение из
пользовательского `handle`:

1. Уходит в зону как uncaught asynchronous error. В чистом Dart-приложении без error-зоны
   это по умолчанию **завершает изолят**.
2. В буферных вариантах пропускается пост-обработка (`_handleData:66-74`): содержимое
   `retryBuffer` **молча теряется**, `_next` для этого события не вызывается, и если новых
   публикаций не будет — `_flushCompleter` зависает.

```dart
final publisher = AsyncPublisher<Log>((log) async => throw Exception('io error'));
log.publisher = publisher;
log.i('hello'); // → uncaught async error; в чистом Dart — падение изолята
```

При этом у `MultiPublisher` (после 0.3.2) есть `onError` — у async-паблишеров аналогичного
механизма нет вовсе, хотя именно они выполняют пользовательский код асинхронно.

### B2 (High). `TypedLazy`: `.resolved` после `.value` возвращает приватный сентинел

`lib/src/utils/lazy.dart:78-88`.

`TypedLazy.value` после конвертации выполняет `_resolved = _noData` (`:82`) — намеренная
очистка памяти. Но геттер `Lazy.resolved` (`:47-54`) при `_resolved == _noData` пытается
разрешить `_unresolved`, который к этому моменту тоже очищен до `_noData` (`:50`).
`resolveToObject(_noData)` возвращает сам `_noData` — и он **отдаётся наружу** как значение
публичного геттера `Object? resolved`. Наружу утекает экземпляр приватного класса `_NoData`
с `toString() == '<no data>'`:

```dart
final lazy = LazyString(() => 'hello');
print(lazy.value);    // hello
print(lazy.resolved); // <no data>  ← экземпляр приватного _NoData
```

Документация класса обещает лишь, что значение «будет очищено», но не что публичный геттер
начнёт возвращать внутренний сентинел.

### B3 (High). `switch` по `FutureOr<Out>`: ветка `Out` стоит первой

`lib/src/async_publishers/async_publisher.dart:126-129`,
`async_publisher_with_param.dart:147-150`, `async_publisher_with_buffer.dart:161-166`,
`async_publisher_with_buffer_and_param.dart:202-205`.

```dart
FutureOr<void> handle(Log log) => switch (format(log)) {
      final Out out => output(out),
      final Future<Out> future => future.then(output),
    };
```

Паттерн `final Out out` проверяется первым. Когда `Out` — `Object?`, `dynamic` или
`FutureOr<...>` (а `Out extends Object?`, так что это легальные и молчаливые инстанциации),
этот паттерн матчит **сам `Future`**, и `output` получает незавершённый `Future` вместо
результата:

```dart
final formatter = AsyncFormatter<Log, Object?>(
  format: (log) async => log.toString(), // Future<Object?>
  output: (out) => print(out),           // печатает "Instance of 'Future<Object?>'"
);
```

Для конкретных типов (`String`, `Map` и т.п.) баг не проявляется — ветки различимы.

### B4 (High). `remainingLogs` считается до завершения асинхронного `format`

`lib/src/async_publishers/async_publisher_with_buffer.dart:157-166`,
`async_publisher_with_buffer_and_param.dart:199-205`.

```dart
final out = format(logs, retryBuffer);
final remainingLogs = List.of(logs)..removeWhere(retryBuffer.contains);
```

`remainingLogs` вычисляется синхронно сразу после вызова `format`. Если `format`
асинхронный и добавляет логи в `retryBuffer` уже внутри своего `await`, эти добавления не
попадут в фильтр — `output` получит список, включающий логи, которые формально отправлены
на retry. Дополнительно `removeWhere(retryBuffer.contains)` — O(n·m) на батч.

### B6 (Medium). `_setLevelPublisher` рвёт пропагацию посреди иерархии

`lib/src/custom_logger/custom_logger.dart:163-175`.

Рекурсивная пропагация пер-уровневого паблишера в саблогеры использует `this[level]`
(`:165`), а `operator []` бросает `StateError` для незарегистрированного уровня (`:91-93`).
Если саблогер не регистрирует уровень родителя, установка паблишера у родителя аварийно
прервётся **посреди обхода**, оставив иерархию наполовину обновлённой. Сейчас это латентно
(саблогеры одного типа имеют одинаковый `registerLevels`), но прямо блокирует пункт TODO.md
«саблогеры другого типа». Заметно, что конструктор `CustomLogger.sub` (`:64-69`) этот случай
уже аккуратно обходит проверкой `_levelLoggers[...] != null` — несимметрично.

### B7 (Medium). `shortName ?? name[0]` — `RangeError` в release и не-BMP символы

`lib/src/custom_logger/custom_level_logger.dart:62-63`.

Пустое `name` защищено только `assert` — в release-сборке вместо понятной ошибки будет
`RangeError` от `name[0]`. Кроме того, `name[0]` берёт UTF-16 code unit: для имени,
начинающегося с символа вне BMP (эмодзи и т.п.), `shortName` станет одиночным суррогатом —
невалидной строкой.

### B8 (Medium). Ошибки `MultiPublisher.flush` минуют `onError`

`lib/src/async_publishers/multi_publisher.dart:70-72`.

`publish` изолирует ошибки каждого паблишера и маршрутизирует их в `onError` (`:56-68`).
`flush` же собирает futures через `.wait`, и ошибки выходят наружу как `ParallelWaitError` —
`onError` не участвует. Поведение покрыто тестом (`test/multi_publisher_test.dart:95`),
то есть выглядит осознанным, но контракт асимметричен и в документации класса не описан.

### B9 (Medium). Жизненный цикл после `close()` не определён

`lib/src/async_publishers/async_publisher.dart:51-60` (и аналогично в остальных).

- `flush()` создаёт новый контроллер и подписку безусловно — вызов после `close()` молча
  «воскрешает» паблишер, `publish` снова начинает работать.
- В буферных вариантах `publish` после `close()` не бросает `StateError` вообще: если буфер
  непуст, лог молча добавляется в список, который уже никогда не будет обработан (тик
  в закрытый контроллер кидает исключение только при пустом буфере).
- Нет публичного признака `isClosed`; повторный `close()` и `flush()`-после-`close()`
  не специфицированы.

## 3. Память и время жизни

### M1 (High). `Finalizer` строго удерживает родителя и не масштабируется

`lib/src/custom_logger/custom_logger.dart:32-34,182-185`.

`_finalizer.attach(sublogger, this)` передаёт **родителя** как finalization value, а
`Finalizer` удерживает value строго, пока жив attached-объект. Итог: каждый живой саблогер
строго пинит родителя (сама иерархия ссылку на родителя не хранит — `WeakReference` в
обратную сторону, но финализатор это сводит на нет для направления «ребёнок → родитель»).
Дополнительно:

- `detach`-токен не передаётся — открепить attachment нельзя;
- финализаторы в Dart не гарантированы к запуску вовсе;
- каждый сработавший коллбек делает O(n) `removeWhere` по `_subloggers`;
- при интенсивном создании короткоживущих саблогеров (паттерн, который README прямо
  рекомендует) список `_subloggers` растёт неограниченно до момента GC.

### M2 (Medium). Подписки на стримы никогда не отменяются

`async_publisher.dart:63`, `async_publisher_with_param.dart:56`,
`async_publisher_with_buffer.dart:36`, `async_publisher_with_buffer_and_param.dart:43`.

Результат `.listen(...)` нигде не сохраняется — `close()` закрывает контроллер, но отмена
подписки и корректная утилизация невозможны. Включённый в конфиге линт
`cancel_subscriptions: error` это не ловит, потому что подписка не присваивается переменной.

### M3 (Low). `CustomLog.zone` удерживает зону, но не используется

`lib/src/custom_logger/custom_log.dart:28`.

Поле заполняется `Zone.current` по умолчанию и живёт столько же, сколько лог (для буферных
паблишеров — до обработки батча), удерживая зону и всё, что она захватила. При этом сама
библиотека поле никак не использует: async-паблишеры выполняют `handle` в зоне подписчика
(зоне создания паблишера), а не в зоне логирования. Поле существует только «на всякий
случай» для пользовательских форматтеров. *Решение автора (Р6, вариант «в»): поле
сохраняется как публичный контракт для пользовательских форматтеров и документируется;
библиотека использовать его не будет (см. SPEC 4.17, опционально 5.6).*

## 4. API и дизайн

### D1 (Low). Barrel экспортирует всё, включая тестовые члены

`lib/logger_builder.dart:5-13` экспортирует все 10 файлов `lib/src/` без `show`/`hide`.
В публичный API попадают: `@visibleForTesting`-геттеры `subLoggersCount`, `levelLinked`,
`publisherLinked` (`custom_logger.dart:76-86`) и недокументированный интерфейс `HasFlush`
(`async_publisher.dart:8-10`).

### D2 (Low). `CustomLevelLogger` без модификатора класса

`custom_level_logger.dart:15` — единственный `abstract class` в пакете; всё остальное
последовательно `base` / `final` / `abstract base` / `interface`. Внешний код может
`implements CustomLevelLogger`, что явно не задумывалось.

### D3 (Medium). Иерархия интерфейсов паблишеров неполна

`async_publisher_with_param.dart:28`, `async_publisher_with_buffer_and_param.dart:34`.

Param-варианты реализуют только `HasFlush` и не являются `CustomLogPublisher` (логично —
они публикуют через адаптер `withParam`), но общего интерфейса «источник с жизненным
циклом» нет: `close()` не входит ни в один интерфейс, поэтому `MultiPublisher` умеет
каскадно `flush`, но не умеет каскадно `close`; обобщённый shutdown-код вынужден проверять
конкретные типы.

### D4 (Low). Дословное дублирование кода

`_AsyncParamPublisher` определён дважды: `async_publisher_with_param.dart:72-99` и
`async_publisher_with_buffer_and_param.dart:100-132`. Логика `_handleData`/`_next`
продублирована между `async_publisher_with_buffer.dart` и
`async_publisher_with_buffer_and_param.dart`. Любой фикс (B1, B5) придётся вносить дважды.

### D5 (Medium). `MultiPublisher` хранит список по ссылке

`multi_publisher.dart:52-53` — `_publishers = publishers` без копии. Внешняя мутация
переданного списка меняет поведение паблишера после создания; геттера/unmodifiable-view
нет, так что это нельзя назвать осознанной «живой» коллекцией.

### D6 (Low). Смешанные стили импортов, self-import barrel-файла

Внутри `lib/src/` соседствуют три стиля: абсолютный self-import
(`async_publisher.dart:3`, `async_publisher_with_param.dart:3`), импорт собственного
barrel-файла целиком (`async_publisher_with_buffer.dart:3`, `multi_publisher.dart:3` —
потенциальный цикл) и относительные импорты. Линт `prefer_relative_imports` в
`analysis_options.yaml` закомментирован, хотя severity для него в `errors:` задан.

### D7 (Low). Отсутствующие API управления иерархией

Нет способа: перечислить зарегистрированные уровни (только `operator []` с исключением),
снять регистрацию уровня, повторно привязать (relink) отвязанный саблогер. Идиома отвязки
`child.level = child.level` существует только в тестах (`test/hierarchy_test.dart:121`) и
нигде не документирована.

### D8 (Low). Несогласованный `fallbackValue` у `LazyString`

`lazy.dart:101` — основной конструктор по умолчанию `'null'`; `lazy.dart:103-105` —
конструктор `.resolved` жёстко задаёт `''` без возможности переопределить.

## 5. Тесты, документация, гигиена

### T1 (Medium). Покрытие тестами фрагментарно

Тесты есть только для иерархии (`hierarchy_test.dart`, 598 строк) и `MultiPublisher`
(109 строк). **Ноль** тестов на: всё async-семейство (порядок обработки, `flush`, `close`,
`sync: true`, `retryBuffer`, ошибки в `handle`), `lazy.dart` целиком, чистку
`WeakReference`/Finalizer, `isLoggable`, все `StateError`-пути (`operator []`, дубль
`registerLevel`, неприаттаченный `logger`), поля `CustomLog`. Все находки B1–B5 и B9
воспроизводимы, но ни одна не была поймана тестами именно из-за этого пробела.

### T2 (Low). Документация публичного API неполна

`public_member_api_docs` в `analysis_options.yaml` закомментирован. Классы задокументированы
хорошо, но у членов пробелы: `HasFlush.flush`, `sync`/`handle`/`close` у всех четырёх
async-баз, константы `Levels` (только групповой комментарий), почти весь `lazy.dart`
(конструкторы, `resolved`, `resolveToObject`, `value`, `convert`, `fallbackValue`),
конструктор `CustomLevelLogger`.

### T3 (Low). Гигиена репозитория

- В `CHANGELOG.md` нет записи о появлении всего семейства async-паблишеров.
- `analysis_options.yaml`: в `errors:` заданы severity для правил, выключенных в `linter:`
  (`prefer_relative_imports`, `no_logic_in_create_state`, `unsafe_html` — два последних
  Flutter/web-специфичны для не-Flutter пакета, а `unsafe_html` к тому же удалён из
  линтера в новых SDK). *Поправка: `flutter_style_todos`, изначально указанный здесь же,
  на самом деле включён в `linter:` — находка к нему не относится.*
- `test/utils/hierarchical_logger.dart:90-102` — закомментированный мёртвый код.
- `TODO.md` на русском при остальной документации на английском. *Решение автора:
  остаётся на русском, исключён из публикации через `.pubignore` (см. SPEC 4.14).*

## 6. Что сделано хорошо

- **Подмена `log`/`noLog` по identity** — элегантное ядро пакета: выключенный уровень стоит
  один вызов пустой функции без аллокаций и проверок; `isEnabled` через
  `identical(_log, _noLog)` — дёшево и корректно.
- **Дизайн под `assert(log.d(...))` и `logging && log.d(...)`** — редкая забота о полном
  вырезании логирования компилятором.
- **`WeakReference`-иерархия** — правильная идея: саблогеры не требуют dispose и не текут
  (проблема M1 — в деталях реализации финализатора, не в замысле).
- **Изоляция ошибок в `MultiPublisher` (0.3.2)** с маршрутизацией в `onError` и честной
  документацией поведения зон — образец, к которому стоит привести и async-паблишеры (B5).
- **Строгий анализатор** (`strict-casts`/`strict-inference`/`strict-raw-types`,
  `discarded_futures`, `unawaited_futures`) и аккуратные класс-модификаторы почти везде.
- **Тесты иерархии** подробны и проверяют тонкую механику link/unlink флагов.

## 7. Кросс-ревью реализации 0.3.3 (Codex + Fable, 2026-07-29)

После реализации milestone 0.3.3 проведено кросс-ревью двумя независимыми
агентами (Codex и Fable-сабагент). Находки и их статус:

| ID | Серьёзность | Нашли | Суть | Статус |
|---|---|---|---|---|
| CR1 | High | оба | Конкурентные `flush()` у небуферных паблишеров: второй flush закрывал непрослушанный контроллер → вечное зависание + потеря логов | **Исправлено**: flush-вызовы сериализованы через цепочку futures (`_flushFuture`); регресс-тесты в `async_publisher_test.dart`, `..._with_param_test.dart` |
| CR2 | High | оба | Бросающий `onError` клинил `BufferedPipeline`: `_finishBatch` пропускался, у подписки не было error-хендлера (невыполненное требование SPEC 4.2 «последний рубеж») | **Исправлено**: `_finishBatch` гарантирован на всех путях, `onError` пользователя обёрнут (его ошибка — в зону), подписки всех конвейеров получили last-resort `onError`; регресс-тесты sync/async |
| CR3 | Medium | оба | `close()` при батче в полёте молча терял логи, принятые до close, вопреки dartdoc | **Исправлено**: `close()` дренирует очередь полностью; retry-записи после close сбрасываются (задокументировано); регресс-тесты |
| CR4 | Medium | Codex | `await close()` изнутри `handle` — взаимная блокировка (close ждёт хендлер, хендлер ждёт close) | **Задокументировано** в dartdoc `close()` всех баз («Do not await this from inside handle»); программная защита отложена |
| F4 | Low | Fable | Дубликат одного экземпляра лога в батче + retry одного вхождения → из `output` исключаются оба; в param-варианте фильтр зависит от пользовательского `Log.==` | **Принято как ограничение**, комментарий в коде уточнён |
| F5 | Info | Fable | После `flush()` небуферных паблишеров uncaught-ошибки уходят в зону вызвавшего flush | **Задокументировано** в dartdoc `flush()` |

Области, подтверждённые чистыми обоими ревьюерами: тик-инвариант конвейера,
`sync: true` реентрантность, порядок веток switch (B3), тайминг
`remainingLogs` (B4), `lazy.dart` целиком, prune/пропагация в `custom_logger`,
валидация имени (B7).

**Второй раунд (перепроверка фиксов, 2026-07-29):** оба ревьюера независимо
подтвердили, что CR1–CR3 действительно исправлены и новых дефектов фиксы не
внесли. Fable повторно прогнал 4 исходных репро и 4 новых адверсариальных
(шторм из 10 перекрывающихся `flush`, `close` между звеньями цепочки flush,
`close` посреди батча с async-разрывом, fire-and-forget `close` из sync-хендлера);
Codex проверил окно непрослушанного контроллера при `close`-во-время-`flush` и
реентрантность last-resort-хендлера. Неблокирующие остаточные заметки:
`flush()` во время дренажа `close()` завершается сразу (по контракту SPEC 4.8);
вечно ретраящий хендлер без `close` крутит тик-цикл — осознанная семантика
retry, без изменений.

**Третий раунд (кросс-ревью milestone 0.4.0, 2026-07-29):** Codex (свежий тред)
+ Fable (продолженный контекст) по дельте v0.3.3 → 0.4.0. HIGH-дефектов нет;
`relink()` и `_waitAll` признаны семантически корректными обоими. Находки и
статус:

| ID | Серьёзность | Нашли | Суть | Статус |
|---|---|---|---|---|
| CR5 | Medium-Low | Fable | Бросающий `onError` в `MultiPublisher.publish` вылетал в точку логирования и обрывал доставку | **Исправлено**: общий `_reportError` с защитой хендлера (вторичная ошибка — в зону) |
| CR6 | Medium | оба | `MultiPublisher` реализовал `Closable`, но не имел закрытого состояния — принимал логи после `close()` | **Исправлено**: `isClosed`, `publish` после close → `StateError`, идемпотентный `close` |
| CR7 | Low | оба | Бросающий `onError` в `flush`/`close` подменял исходную ошибку и ломал контракт «completes normally» | **Исправлено**: маршрутизация через защищённый `_reportError` |
| CR8 | Medium | Codex | `CustomLogger.sub` вызывал переопределяемый `relink()` из конструктора суперкласса — сабкласс с `late`-полем падал бы при конструировании | **Исправлено**: логика в приватном `_relink()`, конструктор минует виртуальный диспатч |
| CR9 | Info | Fable | Риск тихого переопределения новых членов `levels`/`relink` полями существующих сабклассов; `levels` — живое представление | **Задокументировано**: предупреждение в CHANGELOG, пометка «live view» в dartdoc |

## 8. Соответствие находок пунктам SPEC.md

| ID | Пункт SPEC | ID | Пункт SPEC |
|---|---|---|---|
| B1 | 4.1 | M2 | 4.10 |
| B5 | 4.2 | M3 | 4.17 → 5.6 |
| B2 | 4.3 | D1 | 4.16 → 5.5 |
| B3 | 4.4 | D2 | 5.3 |
| B4 | 4.5 | D3 | 5.2 |
| B6 | 4.7 | D4 | 4.11 |
| B7 | 4.6 | D5 | 5.4 |
| B8 | 5.1 | D6 | 4.12 |
| B9 | 4.8 | D7 | 5.7 |
| M1 | 4.9 | D8 | 4.13 |
| T1 | раздел 8 | T2 | 4.15 → 5.8 |
| T3 | 4.14 | | |
