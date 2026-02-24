# TODO

- Саблогеры другого типа
- AsyncLogBuilder
- MultiLogPrinter/MultiLogBuilder ???

## README.md
- AsyncLogPrinter
- Использование в пакетах
- Почему не if (logging)?
- Добавить секцию "Common Mistakes" с наглядными примерами:
  log.i('expensive: ${compute()}'); // плохо (вычисляется всегда)
  log.i(() => 'expensive: ${compute()}'); // хорошо
  Добавить lint rule в analysis_options.yaml пакета? (сложно, но можно
  попробовать через custom lint).
- Добавить раздел "Частые сценарии":
  Как логировать в файл.
  Как добавить timestamp.
  Как покрасить логи (расширить пример с ansi_escape_codes).
  Как интегрировать с riverpod/provider (для Flutter-библиотек).
  Как тестировать код с логгером.
