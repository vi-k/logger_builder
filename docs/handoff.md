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

## В работе

Взят пункт бэклога про реентерабельность `transformer`. Сделана
и закоммичена **документационная часть**: предупреждения в dartdoc
у `CustomLogger.transformer`, `TransformPublisher` и типа
`LogTransformer`. Поведение проверено замером, а не по описанию: один
реентерабельный вызов даёт ~2700 опубликованных дублей при одном
`StackOverflowError` в зону (`TransformPublisher` — ~2000).

Остаток пункта — опциональный guard, детектирующий реентерабельный
`publishLog`, — ждёт решения владельца и лежит в `docs/backlog.md`.

Изменение только в dartdoc, версия не поднята и `CHANGELOG.md` не
тронут: до пользователей это доедет только релизом 0.5.1, решение
о котором за владельцем.

## Открытые проблемы

**README и все примеры учат обходить `transformer`.** Четыре логгера
в `example/logger_builder_examples/lib/` (`simple_logger`,
`complex_logger`, `hierarchical_logger`, `json_reporter`) и README
(строки ~484 и ~496) в `processLog` вызывают `publisher.publish(...)`
напрямую, а не `publishLog(...)`. Это ровно тот случай, про который
предупреждает CHANGELOG 0.5.0: `CustomLogger.transformer` для таких
логгеров молча не работает. Мигрирован только
`test/utils/hierarchical_logger.dart`. Правки не заказывались —
предложить владельцу.

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
