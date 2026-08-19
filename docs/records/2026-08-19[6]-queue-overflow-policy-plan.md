> **Состояние на 2026-08-19:** план составлен, исполнение начато.
> **Что это:** пошаговый план внедрения `maxQueueSize` и политики
> «отбрасывать новый» по утверждённому дизайну.
> **Связанные записи:** `2026-08-19[5]-queue-overflow-policy-design.md`
> (дизайн, который этот план раскладывает), `2026-08-16[4]` (находка `M10`).

# План: граница очереди и политика при переполнении

**Цель.** Дать всем четырём асинхронным паблишерам границу очереди
(`maxQueueSize`, по умолчанию 10 000, `null` — отказ от границы) и
политику «переполнение отбрасывает новый лог, сообщая о нём в
`onDropped`».

**Устройство.** Счётчик принятых-но-не-обработанных записей в обоих
движках (`AsyncPipeline`, `BufferedPipeline`); проверка в `add`;
декремент в точках, где запись перестаёт быть в полёте. Фасады получают
`maxQueueSize`, небуферизованная пара — ещё и `onDropped`.

**Дизайн:** `docs/records/2026-08-19[5]-queue-overflow-policy-design.md`.

## Общие ограничения

Действуют в каждой задаче:

- пол SDK `^3.6.0`; всё, чего нет в 3.6.0, использовать нельзя;
- `dart analyze --fatal-infos` — 0 issues; `dart format` — чисто;
- 80 колонок в коде и в markdown;
- каждый публичный член экспортируемого класса — с dartdoc
  (`public_member_api_docs`); файлы в `internal/` от правила освобождены
  файловым `ignore_for_file`;
- тесты детерминированные: `pumpUntil` из `test/utils/wait.dart`, не
  фиксированные задержки (кроме случаев, где проверяется нижняя граница);
- сначала красный тест, потом код (`docs/conventions.md` §3);
- сообщения коммитов по-английски, с префиксом Conventional Commits;
- **публикация запрещена** без отдельного запроса владельца
  (`AGENTS.md` §5).

---

## Задача 1. Небуферизованная лог-пара

**Файлы:**
- Изменить: `lib/src/async_publishers/internal/async_pipeline.dart`
- Изменить: `lib/src/async_publishers/async_publisher.dart`
- Создать: `test/queue_overflow_test.dart`

**Интерфейсы, на которые опираются следующие задачи:**
- `AsyncPipeline<E>` получает поля `int? maxQueueSize` и
  `void Function(E entry)? onDropped` (оба именованные, оба
  необязательные, `maxQueueSize` без умолчания — умолчание задаёт фасад);
- `_AsyncFacade<E>` получает поле `final int? maxQueueSize` (умолчание
  `10000`) и абстрактный геттер
  `void Function(E entry)? get _droppedHandler`;
- `AsyncPublisherBase<Log>` получает поле
  `final void Function(Log log)? onDropped`.

- [ ] **Шаг 1. Красный тест**

Создать `test/queue_overflow_test.dart`:

```dart
import 'dart:async';

import 'package:logger_builder/logger_builder.dart';
import 'package:test/test.dart';

import 'utils/hierarchical_logger.dart';

Logger makeLogger(CustomLogPublisher<Log> publisher) => Logger('test')
  ..level = Levels.all
  ..publisher = publisher;

void main() {
  group('AsyncPublisher', () {
    test('a full queue refuses the incoming log', () async {
      final gate = Completer<void>();
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) => gate.future,
        maxQueueSize: 2,
        onDropped: (log) => dropped.add(log.message),
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['three']);

      gate.complete();
      await publisher.close();
    });

    test('acceptance resumes once the queue drains', () async {
      final gate = Completer<void>();
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) async {
          await gate.future;
          handled.add(log.message);
        },
        maxQueueSize: 2,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher)
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['three']);

      gate.complete();
      await publisher.flush();
      expect(handled, ['one', 'two']);

      log.i('four');
      await publisher.flush();

      expect(handled, ['one', 'two', 'four']);
      expect(dropped, ['three']);
      await publisher.close();
    });

    test('maxQueueSize: null keeps the queue unbounded', () async {
      final gate = Completer<void>();
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) async {
          await gate.future;
          handled.add(log.message);
        },
        maxQueueSize: null,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher);
      for (var i = 0; i < 50; i++) {
        log.i('$i');
      }

      expect(dropped, isEmpty);

      gate.complete();
      await publisher.close();

      expect(handled, hasLength(50));
    });

    test('maxQueueSize: 0 is a programming error', () {
      expect(
        () => AsyncPublisher<Log>((_) {}, maxQueueSize: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
```

- [ ] **Шаг 2. Убедиться, что тест падает**

`dart test test/queue_overflow_test.dart`
Ожидается: не компилируется — у `AsyncPublisher` нет ни `maxQueueSize`,
ни `onDropped`.

- [ ] **Шаг 3. Движок: счётчик, проверка, отчёт**

В `internal/async_pipeline.dart` добавить поля рядом с `onError`:

```dart
  final void Function(E entry)? onDropped;
  final int? maxQueueSize;
```

в конструктор — `this.onDropped,` и `this.maxQueueSize,`; рядом с
остальным состоянием:

```dart
  // Accepted and not yet handled, including the entry a paused `asyncMap`
  // is holding. Counted rather than measured: the entries sit inside the
  // StreamController, which shows neither its contents nor their number.
  int _pending = 0;
```

`add` и хвост движка:

```dart
  void add(E entry) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    if (maxQueueSize case final limit? when _pending >= limit) {
      _reportDropped(entry);

      return;
    }

    _pending++;
    _controller.add(entry);
  }
```

```dart
  FutureOr<void> _guardedHandle(E entry) {
    try {
      final result = handle(entry);
      if (result is Future<void>) {
        return result.onError<Object>(_reportError).whenComplete(_finished);
      }
    } on Object catch (error, stackTrace) {
      _reportError(error, stackTrace);
    }

    _finished();
  }

  void _finished() => _pending--;

  void _reportDropped(E entry) {
    if (onDropped case final onDropped?) {
      // A throwing handler must not derail publishing.
      guarded(() => onDropped(entry));
    }
  }
```

- [ ] **Шаг 4. Фасад: настройка, умолчание, проверка нуля**

В `async_publisher.dart`, в `_AsyncFacade`, после поля `onError`:

```dart
  /// The most log events the queue accepts before it starts refusing them.
  ///
  /// Counts what has been accepted and not yet handled: the events waiting
  /// in the queue plus the one being handled right now. At the limit it is
  /// the *incoming* event that is refused — it goes to `onDropped` and
  /// never enters the queue. Everything already accepted is still
  /// delivered, so [flush] and [close] promise exactly what they promised
  /// before.
  ///
  /// The default is 10 000 events. At a thousand logs a second that is ten
  /// seconds of a sink that is not draining — an outage rather than a
  /// burst.
  ///
  /// `null` gives the bound up on purpose: the queue then grows until the
  /// process runs out of memory. That is the right trade only when the
  /// input is bounded elsewhere and losing a log is worse than dying.
  final int? maxQueueSize;
```

конструктор базы:

```dart
  _AsyncFacade({
    this.sync = false,
    this.onError,
    this.maxQueueSize = 10000,
  }) : assert(
          maxQueueSize == null || maxQueueSize > 0,
          'maxQueueSize must be null or positive: a queue of zero would '
          'refuse every log',
        ) {
```

и в теле конструктора, в вызов `AsyncPipeline<E>(...)`, добавить:

```dart
      onDropped: _droppedHandler,
      maxQueueSize: maxQueueSize,
```

рядом с `_entryHandler` объявить:

```dart
  /// What the queue calls for an entry it refused.
  ///
  /// A function the subclass hands over rather than a method it overrides,
  /// for the same reason as [_entryHandler]: the two facades disagree about
  /// the shape of the callback the user writes.
  void Function(E entry)? get _droppedHandler;
```

- [ ] **Шаг 5. `AsyncPublisherBase`: свой `onDropped`**

```dart
  /// Called with a log the queue refused because it was full.
  ///
  /// The log is not published and never will be: [maxQueueSize] was
  /// reached when it arrived. Without this callback the loss leaves no
  /// trace — no error, no counter. Use it to persist the log somewhere
  /// durable, or at least to count what the pressure costs.
  ///
  /// A throwing handler does not derail publishing: its own error goes to
  /// the current zone.
  final void Function(Log log)? onDropped;

  /// Creates the publisher and starts its processing queue.
  AsyncPublisherBase({
    super.sync,
    super.onError,
    this.onDropped,
    super.maxQueueSize,
  });
```

и рядом с `_entryHandler`:

```dart
  @override
  void Function(Log log)? get _droppedHandler => onDropped;
```

В `AsyncPublisher` и `AsyncFormatter` добавить в конструкторы
`super.onDropped,` и `super.maxQueueSize,` (после существующих
`super.sync, super.onError`).

- [ ] **Шаг 6. Тест зелёный**

`dart test test/queue_overflow_test.dart` — 4 теста проходят.
`dart analyze --fatal-infos` — 0 issues. `dart format .` — чисто.
`dart test` целиком — прежние 293 плюс 4.

- [ ] **Шаг 7. Мутация**

Убрать проверку лимита из `AsyncPipeline.add` — тест «a full queue
refuses the incoming log» обязан упасть. Вернуть.

- [ ] **Шаг 8. Коммит**

```bash
git add lib/src/async_publishers/internal/async_pipeline.dart \
        lib/src/async_publishers/async_publisher.dart \
        test/queue_overflow_test.dart
git commit
```
Сообщение: `feat(async_publishers): bound the queue of the log-only
publisher` с объяснением политики.

---

## Задача 2. Небуферизованная параметрическая пара

**Файлы:**
- Изменить: `lib/src/async_publishers/async_publisher_with_param.dart`
- Изменить: `test/queue_overflow_test.dart`

**Интерфейсы:**
- потребляет `_droppedHandler` и `maxQueueSize` из задачи 1;
- `AsyncPublisherWithParamBase<Param, Log>` получает
  `final void Function(Param param, Log log)? onDropped`.

- [ ] **Шаг 1. Красный тест**

Добавить в `test/queue_overflow_test.dart` группу:

```dart
  group('AsyncPublisherWithParam', () {
    test('a full queue refuses the incoming entry with its param', () async {
      final gate = Completer<void>();
      final dropped = <String>[];
      final publisher = AsyncPublisherWithParam<String, Log>(
        (param, log) => gate.future,
        maxQueueSize: 2,
        onDropped: (param, log) => dropped.add('$param:${log.message}'),
      );
      makeLogger(publisher.withParam('file'))
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['file:three']);

      gate.complete();
      await publisher.close();
    });
  });
```

- [ ] **Шаг 2. Убедиться, что падает**

`dart test test/queue_overflow_test.dart -n 'AsyncPublisherWithParam'`
Ожидается: не компилируется.

- [ ] **Шаг 3. Реализация**

В `AsyncPublisherWithParamBase`:

```dart
  /// Called with an entry the queue refused because it was full.
  ///
  /// The log is not published and never will be: [maxQueueSize] was
  /// reached when it arrived. Without this callback the loss leaves no
  /// trace — no error, no counter. The parameter comes with it, so an
  /// adapter's own losses are told apart from its neighbours'.
  ///
  /// A throwing handler does not derail publishing: its own error goes to
  /// the current zone.
  final void Function(Param param, Log log)? onDropped;

  /// Creates the publisher and starts its processing queue.
  AsyncPublisherWithParamBase({
    super.sync,
    super.onError,
    this.onDropped,
    super.maxQueueSize,
  });

  @override
  void Function((Param, Log) entry)? get _droppedHandler {
    if (onDropped case final onDropped?) {
      return (entry) => onDropped(entry.$1, entry.$2);
    }

    return null;
  }
```

В `AsyncPublisherWithParam` и `AsyncFormatterWithParam` — `super.onDropped,`
и `super.maxQueueSize,` в конструкторы.

- [ ] **Шаг 4. Зелёный + мутация**

`dart test`, `dart analyze --fatal-infos`, `dart format`. Мутация: вернуть
`_droppedHandler` к `null` — новый тест падает.

- [ ] **Шаг 5. Коммит**

`feat(async_publishers): bound the queue of the parameterised publisher`

---

## Задача 3. Буферизованная пара

**Файлы:**
- Изменить: `lib/src/async_publishers/internal/buffered_pipeline.dart`
- Изменить: `lib/src/async_publishers/async_publisher_with_buffer.dart`
- Изменить: `lib/src/async_publishers/async_publisher_with_buffer_and_param.dart`
- Изменить: `test/queue_overflow_test.dart`

**Интерфейсы:**
- `BufferedPipeline<E>` получает `final int? maxQueueSize`;
- `_BufferedFacade<E>` получает `final int? maxQueueSize` (умолчание
  `10000`, тот же `assert`), `onDropped` там уже есть и не меняется.

- [ ] **Шаг 1. Красный тест**

```dart
  group('AsyncPublisherWithBuffer', () {
    test('a full buffer refuses the incoming log', () async {
      final gate = Completer<void>();
      final dropped = <String?>[];
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retryBuffer) => gate.future,
        maxQueueSize: 2,
        onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['three']);

      gate.complete();
      await publisher.close();
    });

    test('a retried batch is not cut by the limit', () async {
      final handled = <String?>[];
      final dropped = <String?>[];
      var attempts = 0;
      final publisher = AsyncPublisherWithBuffer<Log>(
        (logs, retryBuffer) {
          attempts++;
          if (attempts == 1) {
            retryBuffer.addAll(logs);

            return;
          }
          handled.addAll(logs.map((log) => log.message));
        },
        maxQueueSize: 2,
        onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
      );
      makeLogger(publisher)
        ..i('one')
        ..i('two');

      await pumpUntil(() => handled.length == 2);

      expect(handled, ['one', 'two']);
      expect(dropped, isEmpty);
      await publisher.close();
    });
  });

  group('AsyncPublisherWithBufferAndParam', () {
    test('a full buffer refuses the incoming entry', () async {
      final gate = Completer<void>();
      final dropped = <String>[];
      final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
        (entries, retryBuffer) => gate.future,
        maxQueueSize: 2,
        onDropped: (entries) => dropped.addAll(
          entries.map((entry) => '${entry.$1}:${entry.$2.message}'),
        ),
      );
      makeLogger(publisher.withParam('db'))
        ..i('one')
        ..i('two')
        ..i('three');

      expect(dropped, ['db:three']);

      gate.complete();
      await publisher.close();
    });
  });
```

Добавить импорт `import 'utils/wait.dart';` в шапку файла.

- [ ] **Шаг 2. Убедиться, что падает**

`dart test test/queue_overflow_test.dart` — три новых теста не
компилируются.

- [ ] **Шаг 3. Движок**

В `internal/buffered_pipeline.dart` — поле рядом с `maxRetries`:

```dart
  final int? maxQueueSize;
```

в конструктор — `this.maxQueueSize,`; рядом с состоянием:

```dart
  // Accepted and not yet finished: what waits in `_entries` plus the batch
  // in flight, which is out of the list but still in memory.
  int _pending = 0;
```

`add`:

```dart
  void add(E entry) {
    if (isClosed) {
      throw StateError('The publisher is closed');
    }

    if (maxQueueSize case final limit? when _pending >= limit) {
      _reportDropped([entry]);

      return;
    }

    _pending++;
    final wasEmpty = _entries.isEmpty;
    _entries.add(entry);
    if (wasEmpty && !_isProcessing) {
      _controller.add(null);
    }
  }
```

`_finish` целиком:

```dart
  void _finish(List<E> entries, List<E> retryBuffer) {
    if (isClosed) {
      // Entries retried after close() would never be processed. Report them
      // rather than losing them without a trace.
      if (retryBuffer.isNotEmpty) {
        _reportDropped(List<E>.of(retryBuffer));
      }
      _pending -= entries.length;
    } else if (retryBuffer.isEmpty) {
      _retryAttempts = 0;
      _batchWasRetried = false;
      _pending -= entries.length;
    } else if (_retryAttempts >= maxRetries) {
      // Out of budget. Dropping is the lesser evil: a batch that fails
      // deterministically is never delivered by retrying either, it just
      // holds the queue, burns a core and keeps the isolate alive.
      _retryAttempts = 0;
      _batchWasRetried = false;
      _reportDropped(List<E>.of(retryBuffer));
      _pending -= entries.length;
    } else {
      _retryAttempts++;
      _batchWasRetried = true;
      final requeued = _inPublishOrder(entries, retryBuffer);
      _entries.insertAll(0, requeued);
      // The batch leaves the count except for what went back into the
      // queue — and a handler may hand back entries that never came from
      // this batch, which were never counted on the way in. Subtracting
      // the difference keeps the count on what is actually held rather
      // than on what was once accepted.
      _pending -= entries.length - requeued.length;
    }
  }
```

- [ ] **Шаг 4. Фасад**

В `_BufferedFacade` (`async_publisher_with_buffer.dart`) — поле
`maxQueueSize` с тем же дартдоком, что в `_AsyncFacade` (слово «events»
заменить на «entries»), тот же `assert` в конструкторе, передача
`maxQueueSize: maxQueueSize` в `BufferedPipeline<E>(...)`.

В `AsyncPublisherWithBufferBase`, `AsyncPublisherWithBufferAndParamBase`
и в четыре конкретных класса — `super.maxQueueSize,` в конструкторы.

- [ ] **Шаг 5. Зелёный + мутация**

`dart test`, `dart analyze --fatal-infos`, `dart format`. Две мутации:
убрать проверку в `add` — падает «a full buffer refuses»; заменить
`_pending -= entries.length - requeued.length` на
`_pending -= entries.length` — падает «a retried batch is not cut»
(счётчик уедет в минус и лимит перестанет срабатывать вообще; проверить,
что тест это ловит, иначе усилить тест).

- [ ] **Шаг 6. Коммит**

`feat(async_publishers): bound the buffered queues`

---

## Задача 4. Контракт по всем восьми классам

**Файлы:**
- Изменить: `test/queue_overflow_test.dart`

Восемь классов — почти копии друг друга, и ревью уже ловило контракт,
который держался в двух из них и не держался в шести. Поэтому граница
проверяется не только на четырёх «своих» классах, но и на всех восьми
разом, как это сделано в `test/lifecycle_contract_test.dart`.

- [ ] **Шаг 1. Красный тест: все восемь**

Каждый строитель отдаёт паблишер, куда логировать, то, что закрывают,
свой шлюз и свой список потерь: тест публикует два лога при лимите 1,
проверяет, что отброшен второй, и убирает за собой.

```dart
typedef _Case = ({
  CustomLogPublisher<Log> sink,
  Closable closable,
  Completer<void> gate,
  List<String?> dropped,
});

final Map<String, _Case Function()> _bounded = {
  'AsyncPublisher': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisher<Log>(
      (log) => gate.future,
      maxQueueSize: 1,
      onDropped: (log) => dropped.add(log.message),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
  'AsyncFormatter': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatter<Log, String?>(
      format: (log) => log.message,
      output: (out) => gate.future,
      maxQueueSize: 1,
      onDropped: (log) => dropped.add(log.message),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
  'AsyncPublisherWithParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisherWithParam<String, Log>(
      (param, log) => gate.future,
      maxQueueSize: 1,
      onDropped: (param, log) => dropped.add(log.message),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
  'AsyncFormatterWithParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatterWithParam<String, Log, String?>(
      format: (param, log) => log.message,
      output: (param, out) => gate.future,
      maxQueueSize: 1,
      onDropped: (param, log) => dropped.add(log.message),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
  'AsyncPublisherWithBuffer': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisherWithBuffer<Log>(
      (logs, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
  'AsyncFormatterWithBuffer': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatterWithBuffer<Log, int>(
      format: (logs, retryBuffer) => logs.length,
      output: (out, logs, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (logs) => dropped.addAll(logs.map((log) => log.message)),
    );

    return (
      sink: publisher,
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
  'AsyncPublisherWithBufferAndParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncPublisherWithBufferAndParam<String, Log>(
      (entries, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (entries) =>
          dropped.addAll(entries.map((entry) => entry.$2.message)),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
  'AsyncFormatterWithBufferAndParam': () {
    final gate = Completer<void>();
    final dropped = <String?>[];
    final publisher = AsyncFormatterWithBufferAndParam<String, Log, int>(
      format: (entries, retryBuffer) => entries.length,
      output: (out, entries, retryBuffer) => gate.future,
      maxQueueSize: 1,
      onDropped: (entries) =>
          dropped.addAll(entries.map((entry) => entry.$2.message)),
    );

    return (
      sink: publisher.withParam('p'),
      closable: publisher,
      gate: gate,
      dropped: dropped
    );
  },
};
```

и сама проверка:

```dart
  group('every publisher refuses when full', () {
    for (final entry in _bounded.entries) {
      test(entry.key, () async {
        final subject = entry.value();
        makeLogger(subject.sink)
          ..i('one')
          ..i('two');

        expect(subject.dropped, ['two'], reason: entry.key);

        subject.gate.complete();
        await subject.closable.close();
      });
    }
  });
```

- [ ] **Шаг 2. Ещё три теста контракта**

```dart
    test('a throwing onDropped does not reach the logging call', () async {
      final gate = Completer<void>();
      final errors = <Object>[];
      late final AsyncPublisher<Log> publisher;
      runZonedGuarded(
        () {
          publisher = AsyncPublisher<Log>(
            (log) => gate.future,
            maxQueueSize: 1,
            onDropped: (log) => throw StateError('boom'),
          );
          makeLogger(publisher)
            ..i('one')
            ..i('two');
        },
        (error, stackTrace) => errors.add(error),
      );

      expect(errors, hasLength(1));

      gate.complete();
      await publisher.close();
    });

    test('a handler that keeps up never trips the limit', () {
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) => handled.add(log.message),
        sync: true,
        maxQueueSize: 1,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher);
      for (var i = 0; i < 100; i++) {
        log.i('$i');
      }

      expect(handled, hasLength(100));
      expect(dropped, isEmpty);
    });

    test('flush and close still complete while logs are being dropped',
        () async {
      final handled = <String?>[];
      final dropped = <String?>[];
      final publisher = AsyncPublisher<Log>(
        (log) async {
          await Future<void>.delayed(Duration.zero);
          handled.add(log.message);
        },
        maxQueueSize: 3,
        onDropped: (log) => dropped.add(log.message),
      );
      final log = makeLogger(publisher);
      for (var i = 0; i < 20; i++) {
        log.i('$i');
      }

      expect(dropped, isNotEmpty);

      await publisher.flush();
      await publisher.close();

      expect(handled.length + dropped.length, 20);
      expect(publisher.isClosed, isTrue);
    });
```

- [ ] **Шаг 3. Зелёный**

`dart test`, `dart analyze --fatal-infos`, `dart format`.

- [ ] **Шаг 4. Коммит**

`test(async_publishers): check the bound on all eight publishers`

---

## Задача 5. Документы

**Файлы:**
- Изменить: `README.md`, `README.ru.md` (одним коммитом!)
- Изменить: `CHANGELOG.md`
- Изменить: `docs/architecture.md`

- [ ] **Шаг 1. README**

Переписать блок `> [!IMPORTANT]` про «All of these queues are
**unbounded**» (около строки 995): очередь ограничена 10 000 записей по
умолчанию, переполнение отбрасывает входящий лог и сообщает о нём в
`onDropped`, `maxQueueSize: null` возвращает прежнее поведение. Убрать
фразу «`onDropped` is not that counter» — теперь он и есть тот счётчик.
Поправить место про файловый паблишер (около строки 1335), где сказано,
что очередь неограниченна.

- [ ] **Шаг 2. README.ru.md** — те же правки, тот же коммит.

- [ ] **Шаг 3. CHANGELOG 0.7.0**

В `[breaking changes]`: очереди всех восьми паблишеров теперь
ограничены 10 000 записями по умолчанию; при переполнении отбрасывается
входящий лог. Прежнее поведение — `maxQueueSize: null`.
В `New`: `maxQueueSize` на всех восьми, `onDropped` у небуферизованной
четвёрки.

- [ ] **Шаг 4. `docs/architecture.md`** — абзац про границу очереди
в разделе про асинхронную доставку.

- [ ] **Шаг 5. Коммит**

`docs: document the queue bound in both READMEs and the changelog`

---

## Задача 6. Замер, проверки, записи

- [ ] **Шаг 1. Бенчмарк A/B/A/B**

Собрать AOT-бинарь из этого дерева и из клона на коммите до задачи 1,
прогнать по очереди дважды каждый, сравнить строки «Asynchronous
publishers». Ожидание: разница внутри sd. Если нет — разобраться до
коммита.

- [ ] **Шаг 2. Полный прогон чеклиста §7**

`dart analyze --fatal-infos`, `dart test`, три прогона с
`--test-randomize-ordering-seed=random`, `dart format`, `dart doc`
(0/0), девять примеров, `dart compile js`/`wasm`, чистый клон на 3.13.0
и на 3.7.0, `flutter analyze` пробного пакета на 3.47 и 3.29,
`dart pub publish --dry-run` в чистом клоне.

- [ ] **Шаг 3. Отчёт** — `docs/records/2026-08-19[7]-...-report.md`:
что сделано, замеры, чем закрыта находка `M10`, вердикт в самой находке
(`2026-08-16[4]`, абзацем в конце находки, прозу не трогать).

- [ ] **Шаг 4. `docs/handoff.md`** — таблица проверок на новый коммит,
пункт 2 «Открытых вопросов» снять, раздел о работе.

- [ ] **Шаг 5. Push и CI** — дождаться четырёх зелёных job'ов.
