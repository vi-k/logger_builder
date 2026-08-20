> **Состояние на 2026-08-16:** сделано и смержено в `main`. `dart analyze`
> снова даёт 0 issues, `dart test` — 136/136, `dart format` — чисто.
> **Что это:** отчёт о волне правок: починка конфигурации анализатора,
> которая ломала CI на Dart SDK 3.13, и устранение дубля конфигурации
> между пакетом и примерами.
> **Связанные записи:** `2026-07-29[1]-baseline-0.3.2-project-review.md`
> (находка T3 — гигиена конфигурации).

# Порядок в analysis_options.yaml и example

## Что было

`dart analyze` возвращал 2 (три warning'а), и CI
(`.github/workflows/dart.yml`) был красным, потому что `dart analyze`
считает warning фатальным:

1. `analysis_options.yaml:6` — `invalid_section_format`: секция
   `analyzer.exclude` записана словарём (`"web/**": true`), а анализатор
   ждёт список.
2. `example/logger_builder_examples/analysis_options.yaml:6` — то же
   самое.
3. `example/.../bin/async_publishers/async_publisher_with_buffer.dart:74`
   — `unawaited_return_in_try_block`.

Плюс два расхождения, не дававших диагностики, но мешавших читать конфиг:
`cancel_subscriptions`/`close_sinks` стояли со значением `error`
в группе `# Warning`, а конфиг примеров был дословной копией корневого
на 263 строки — и уже разошёлся с ним: правки по находке T3
(мёртвые severity `no_logic_in_create_state`, `unsafe_html`) применили
только к корневому файлу.

## Что сделано

- `analyzer.exclude` в корневом конфиге переписан в списочный синтаксис;
  сами записи (`web/**`, `build/**`, `assets/**`) сохранены — файл служит
  владельцу шаблоном и для других проектов.
- `cancel_subscriptions: error` и `close_sinks: error` переставлены
  в группу `# Error`.
- Конфиг примеров заменён на `include: ../../analysis_options.yaml`
  с единственным переопределением `public_member_api_docs: false`.
  Так расхождение между двумя файлами больше невозможно.
- В примере `async_publisher_with_buffer.dart` добавлен `await` перед
  `logs.map(defaultAsyncFormat).wait` внутри `try`. Это не косметика:
  без `await` ошибка форматирования уходила мимо соседнего `catch`,
  и логи не попадали в `retryBuffer` — то есть пример учил неправильному.

## Проверено

- `dart analyze` — 0 issues (был код возврата 2).
- `dart test` — 136/136.
- `dart format --output=none --set-exit-if-changed .` — чисто.
- Правленый пример запущен: батчи форматируются и выводятся как раньше.
- Проверено, что правила корневого конфига действительно доезжают
  до примеров через `include` (пробный файл ловит `prefer_single_quotes`
  и `prefer_const_declarations` — их нет в `package:lints/recommended`).
- Переопределение `prefer_relative_imports: false`, бывшее в старом
  конфиге примеров, оказалось ненужным: без него анализ чист. Не
  перенесено.
- `dart pub publish --dry-run` — оба `analysis_options.yaml` входят
  в архив, поэтому относительный `include` резолвится и в опубликованном
  пакете.
