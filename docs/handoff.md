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

Поверх релиза лежат два коммита, оба запушены в `origin/main`
(`main` == `origin/main` == `3290dfe`):

1. Первичная настройка под работу с агентами: `AGENTS.md` как точка
   входа, `CLAUDE.md` со ссылкой на него, документы в `docs/`, история —
   в `docs/records/`. Корневые `TODO.md`, `REVIEW.md` и `SPEC.md`
   разобраны по местам, `.pubignore` обновлён.
2. Порядок в конфигурации анализатора — см.
   `docs/records/2026-08-16[1]-analyzer-cleanup-report.md`.

## Состояние проверок

Dart SDK 3.13.0 (stable):

| Проверка | Результат |
|---|---|
| `dart analyze` | 0 issues |
| `dart test` | 136/136 зелёные |
| `dart format --output=none --set-exit-if-changed .` | чисто |
| `dart pub publish --dry-run` | 0 предупреждений |

## Открытые проблемы

**У волны 0.5.0 нет записи в `docs/records/`.** Что вошло в релиз, видно
по `CHANGELOG.md` (`LogTransformer`, `CustomLogger.transformer`,
`CustomLevelLogger.publishLog`, `TransformPublisher`, `CustomLog.copy`)
и по коммитам `313e3f0..89730fb`, но отчёта о волне и о её финальном
ревью не сохранилось. Одна находка того ревью дошла до бэклога
(предупреждение о реентерабельности `transformer`).

## Что дальше

Кода в работе нет — следующий шаг за владельцем. Предложить к разбору
пункты `docs/backlog.md`: саблогеры другого типа, dartdoc про
реентерабельность `transformer`, доработки README.
