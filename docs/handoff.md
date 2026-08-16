# Текущее состояние проекта

> Обновлено: 2026-08-16

Только текущее состояние. История — в `docs/records/`, пожелания
владельца — в `docs/backlog.md`, устройство пакета — в
`docs/architecture.md`.

## Где мы

Пакет `logger_builder` 0.5.0 выпущен и опубликован на pub.dev
(последняя версия там — 0.5.0). Ветка `main`, последний релизный
коммит — `89730fb Release 0.5.0`, тег `v0.5.0`. Активной работы над
кодом сейчас нет.

Первичная настройка проекта под работу с агентами сделана коммитом
`Set up agent-facing docs` поверх `df590a3`: `AGENTS.md` как точка входа,
`CLAUDE.md` со ссылкой на него, документы в `docs/`, история —
в `docs/records/`. Корневые `TODO.md`, `REVIEW.md` и `SPEC.md` разобраны
по местам, `.pubignore` обновлён (`dart pub publish --dry-run` — 0
предупреждений, внутренние документы в пакет не попадают). Коммит
локальный, на `origin/main` ещё не запушен.

## Состояние проверок

Dart SDK 3.13.0 (stable):

| Проверка | Результат |
|---|---|
| `dart test` | 136/136 зелёные |
| `dart format --output=none --set-exit-if-changed .` | чисто |
| `dart analyze` | **3 issue, код возврата 2** |

## Открытые проблемы

**CI красный на актуальном стабильном SDK.** `dart analyze` (его и гоняет
`.github/workflows/dart.yml`) считает warning фатальным, а сейчас их
три:

1. `analysis_options.yaml:6:5` — `invalid_section_format`: секция
   `analyzer.exclude` записана словарём (`"web/**": true`), а новый
   анализатор ждёт список (`- "web/**"`).
2. `example/logger_builder_examples/analysis_options.yaml:6:5` — то же
   самое.
3. `example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer.dart:74:9`
   — `unawaited_return_in_try_block`: `return logs.map(...).wait` внутри
   `try` без `await`, из-за чего `catch` рядом не поймает ошибку.

Ни одна из трёх не затрагивает `lib/` — это конфиг и пример. Правки
владельцем не заказывались; предложить их в работу.

**У волны 0.5.0 нет записи в `docs/records/`.** Что вошло в релиз, видно
по `CHANGELOG.md` (`LogTransformer`, `CustomLogger.transformer`,
`CustomLevelLogger.publishLog`, `TransformPublisher`, `CustomLog.copy`)
и по коммитам `313e3f0..89730fb`, но отчёта о волне и о её финальном
ревью не сохранилось. Одна находка того ревью дошла до бэклога
(предупреждение о реентерабельности `transformer`).

## Что дальше

Кода в работе нет — следующий шаг за владельцем. Предложить к разбору:

- пункты `docs/backlog.md` (саблогеры другого типа, dartdoc про
  реентерабельность `transformer`, доработки README);
- три issue анализатора выше, чтобы вернуть CI в зелёное.
