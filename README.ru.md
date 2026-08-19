[![Dart CI](https://github.com/vi-k/logger_builder/actions/workflows/dart.yml/badge.svg)](https://github.com/vi-k/logger_builder/actions/workflows/dart.yml)
[![Pub Publisher](https://img.shields.io/pub/publisher/logger_builder)](https://pub.dev/publishers/yet-another.dev/packages)
![Pub Version](https://img.shields.io/pub/v/logger_builder)
![GitHub License](https://img.shields.io/github/license/vi-k/logger_builder)

*Перевод. Оригинал — [README.md](README.md); он же публикуется на pub.dev.
Эта версия живёт только в репозитории.*

Конструктор собственных настраиваемых иерархических логгеров для Dart
с хорошей производительностью в выключенном состоянии.

```sh
dart pub add logger_builder
```

## Возможности

- **Свои логгеры**: собственные классы логгеров на основе `CustomLogger`
  с теми методами логирования, записями и свойствами, которые нужны вам.
- **Иерархические логгеры**: встроенная поддержка иерархий, в которых
  саблогеры наследуют настройки (уровни, паблишеры) от родителей и при
  необходимости переопределяют их.
- **Отложенные вычисления**: утилиты `Lazy` и `LazyString` избавляют от
  дорогих операций (интерполяции строк, кодирования в JSON), когда
  уровень логирования выключен.
- **Асинхронные и буферизованные паблишеры**: базовые классы вроде
  `AsyncPublisherBase` — чтобы выводить логи асинхронно или копить их
  в буфере перед отправкой (например, в сервис аналитики).
- **Трансформеры**: `LogTransformer` на логгере или на отдельном
  приёмнике маскирует секреты и персональные данные либо целиком
  отбрасывает запрещённые логи — до того, как они куда-либо попадут.
- **Гибкие форматирование и вывод**: логгеры разделяют шаг
  **форматирования** (превращение записи в строку или другой объект)
  и шаг **вывода** (что с готовым объектом делать — например, печатать
  в консоль).


## Оглавление

- [Что умеет этот конструктор?](#что-умеет-этот-конструктор)
- [Производительность](#производительность)
- [Почему не просто `if (logging)`?](#почему-не-просто-if-logging)
- [Как сделать свой логгер?](#как-сделать-свой-логгер)
- [Отложенные вычисления](#отложенные-вычисления)
- [Свои паблишеры](#свои-паблишеры)
- [Асинхронные паблишеры](#асинхронные-паблишеры)
- [Несколько паблишеров](#несколько-паблишеров)
- [Иерархические логгеры](#иерархические-логгеры)
- [Трансформеры](#трансформеры)
- [Типовые сценарии](#типовые-сценарии)
- [Типичные ошибки](#типичные-ошибки)
- [logger_builder в вашем собственном пакете](#logger_builder-в-вашем-собственном-пакете)
- [Примеры](#примеры)

## Что умеет этот конструктор?

Дальше — примеры того, какие логгеры можно построить: что можно сделать.
Как это сделать, разбирается ниже.

> [!NOTE]
> Фрагменты ниже показывают вывод, который вы получите, **когда логирование
> включено**. Для этого нужны две вещи, и у только что созданного логгера
> нет ни одной:
>
> - `..level = Levels.all` (или любой другой порог) — свежепостроенный
>   логгер стоит на `Levels.off`. Такой умолчательный уровень выбран
>   намеренно, см.
>   [logger_builder в вашем собственном пакете](#logger_builder-в-вашем-собственном-пакете);
> - `..publisher = ...` — каждый уровень стартует на no-op-паблишере,
>   который выбрасывает всё, что получает.
>
> Ошибётесь в одном из двух — получите тишину без намёка на то, в чём
> дело: ненастроенный уровень по-прежнему сообщает `isEnabled == true`,
> потому что он и правда включён — просто публикует в никуда.

**Свои методы логирования**

Какие методы логирования будут у вашего логгера, решаете вы сами.

Например, такие:

```dart
final log = Logger();
log.info('Hello');
log.error('Error', error: Exception('Test'));
```

Или такие:

```dart
final log = Logger();
log.v('Verbose info');
log.d('Debug info');
log.w('Warning info');
log.e('Error', error: Exception('Test'));
log.f('Fatal error', error: Exception('Test'));
```

**Любые нужные вам параметры**

Например, такие:

```dart
final log = Logger();
log.i('MyClass', 'Info message');
```

Или такие:

```dart
final log = Logger();
log.i(
  'Info message',
  unit: 'MyClass',
  method: 'myMethod',
  tags: ['tag1', 'tag2'],
  time: DateTime.now(),
  zone: Zone.root,
);
```

**Иерархические логгеры**

Можно создавать вложенные логгеры, связанные с основным. Освобождать их
не нужно: родитель держит их через слабые ссылки, поэтому, как только вы
перестали ссылаться на саблогер, он собирается сборщиком мусора и при
следующем обходе вычёркивается из родителя. Значит, их можно спокойно
создавать в каждой функции или в каждом узле, где они нужны. Правила
наследования — в разделе
[Иерархические логгеры](#иерархические-логгеры).

```dart
final log = Logger('app');
final authLog = log.child('auth');
final loginLog = authLog.child('login');
final logoutLog = authLog.child('logout');

log.i('App started');                     // app | App started
authLog.i('Check user authentification'); // app | auth | Check user authentification
loginLog.i('User login');                 // app | auth | login | User login
logoutLog.i('User logout');               // app | auth | logout | User logout
```

`child` — не метод пакета: пакет даёт защищённый конструктор
`CustomLogger.sub`, а вы открываете его под тем именем, которое лучше
читается. Определён он у `Logger` из раздела
[Иерархические логгеры](#иерархические-логгеры).

Вид `app | auth | login` в комментариях тоже не берётся сам собой.
Имени логгера пакет не знает вовсе: этот вид даёт логгер побогаче — тот,
что в примере ниже, — у которого `Log` несёт поле `path` и склеивает его
через ` | `. `Logger` из раздела
[Иерархические логгеры](#иерархические-логгеры) склеивает через точку
и путь не печатает вообще.

Смотрите пример: [hierarchical_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/hierarchical_logger.dart).

**Любой тип вывода**

Тип вывода вовсе не обязан быть `String`. Это может быть, например,
готовый json или тип, подготовленный к преобразованию в json:

```dart
final log = JsonReporter()
  ..level = Levels.all
  ..publisher = const DefaultJsonPublisher();
log.i('info-event', data: {'id': 2, 'data': 'Info data'});
// {"level":"info","timestamp":1786903488805201,"event":"info-event",
//  "data":{"id":2,"data":"Info data"}}
```

Смотрите пример: [json_reporter.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/json_reporter.dart).

**Настраиваемое форматирование**

```dart
final log = Logger();
log.publisher = CustomLogPublisher(
  (log) {
    print('[${log.shortLevelName}] ${log.message}');
  },
);
```

Форматирование доступно не только на этапе создания класса логгера, но
и позже, в реальном времени. Это позволяет делать логгеры для пакетов:
вы пишете пакет и логирование в нём, полезное не только вам как автору
пакета, но и его пользователям. И вы даёте пользователю не только доступ
к логам, но и возможность настроить формат вывода так, чтобы ВАШИ логи
стали неотъемлемой частью логов ПОЛЬЗОВАТЕЛЯ — в том виде, в каком он
хочет их видеть.

```dart
final log = Logger('package');
// Ваши логи:
log.i('feature', 'Info message');
// [i] package | feature | Info message

// Логи пользователя после настройки, для примера:
log.publisher = ...;
// 2026-02-23 19:19:09.123 [INFO] package/feature/ Info message
```

**Настраиваемый вывод**

Форматирование и вывод можно разделить — тогда для разных уровней
логирования настраивается разное форматирование при едином выводе:

```dart
import 'package:ansi_escape_codes/style.dart';

String format(Log log) => '[${log.shortLevelName}] ${log.message}';

final log = Logger()
  ..publisher = CustomLogFormatter(
    format: format,
    output: print,
  )
  ..[Levels.error].publisher = CustomLogFormatter(
    format: (log) => Styles.red(format(log)),
    output: print,
  );
```

Или наоборот: единое форматирование, но разный вывод для разных уровней.

```dart
import 'package:ansi_escape_codes/style.dart';

String format(Log log) => '[${log.shortLevelName}] ${log.message}';

final log = Logger()
  ..publisher = CustomLogFormatter(
    format: format,
    output: print,
  )
  ..[Levels.error].publisher = CustomLogFormatter(
    format: format,
    output: (str) => print(Styles.red(str)),
  );
```


## Производительность

При логировании часто не так важно, сколько времени тратится на сам
вывод лога, зато очень важно, сколько времени логирование отнимает,
когда оно выключено.

**Базовый уровень выключения логгера**

```dart
final log = Logger()..level = Levels.off;
log.d('This will not be logged');
```

Если логирование выключено, под капотом вызывается no-op-функция. Ни
вычислений, ни проверок. Просто один вызов пустой функции, которая, как
правило, хорошо оптимизируется компилятором.

**Отложенное вычисление параметров**

Но при обычном использовании параметры функции всё равно будут
вычислены. Поэтому пакет предоставляет утилиты для отложенных
вычислений:

```dart
final log = Logger();
...
log.d(() => expensiveCalculation());
// или:
log.d(expensiveCalculation);
```

**Полное удаление кода логирования**

Для более требовательных случаев, когда нужна максимальная
производительность, логгер спроектирован под удобное использование
с ассертами и константами.

Ассерты — известный приём, позволяющий вырезать из кода не только
лишние проверки, но и функции логирования. Обычно это выглядит так:

```dart
assert(() {
  log.d('Debug info');
  return true;
}());
```

Довольно громоздко! Пакет даёт возможность писать так:

```dart
assert(log.d('Debug info'));
```

А вместо:

```dart
const logging = bool.fromEnvironment('logging');
if (logging) log.d('Debug info');
```

можно писать так:

```dart
logging && log.d('Debug info 1');
```

Результат в обоих случаях будет одинаковым. Это просто сахар.

Важно тут только одно: когда вы выключаете ассерты или свою константу,
код логирования удаляется компилятором. Это не просто `if (false)`. Это
полное удаление.

**Глубина ничего не стоит.** Саблогер обходится ровно как корень, и ради
этого унаследованные настройки хранятся копиями, а не разрешаются на
каждом вызове. Замерено на глубинах 0, 1, 5 и 20, AOT: 83.2, 83.2, 83.6,
83.5 нс при включённом уровне и 1.66, 1.78, 1.72, 1.77 нс при выключенном.
Плоско, в пределах sd каждой цифры.

Исключение — то, что ваш собственный паблишер разрешает на каждый лог.
У `Logger` из примера есть лениво собираемый `path`, и паблишер, который
его читает, платит за обход: те же четыре глубины дают 101.7, 103.5, 112.6
и 152.0 нс — примерно 2.5 нс на уровень. Эта цена ваша, а не пакета,
и приходит она, только если паблишер спросит путь.

Бенчмарки можно посмотреть здесь: [benchmarks.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/benchmarks.dart).


## Почему не просто `if (logging)`?

Если ваши потребности закрываются вот этим

```dart
const logging = bool.fromEnvironment('logging');
if (logging) print('User $id logged in');
```

то так и продолжайте. Это ничего не стоит, и пакет не просит от этого
отказываться: как показано выше, `logging && log.i(...)` — тот же самый
приём, и вырезается он так же полностью.

Разница в том, **когда** щёлкает переключатель.

`if (logging)` — переключатель **времени компиляции**. Одна константа
включает или выключает логирование всей программы, а приёмник — `print`
— вписан в каждую точку вызова. Это нормально, пока единственный
читатель — вы сами, в своём терминале, прямо сейчас.

Логгер — переключатель **времени выполнения**, и он даёт четыре вещи,
которых голый `print` дать не может:

- **Избирательность.** `Levels.off` для приложения и `Levels.all` для
  `authLog`: одна шумная подсистема — без перекомпиляции и без того,
  чтобы утонуть во всём остальном.
- **Уровни.** У `print` ровно одна степень важности. Тому, кто ловит
  баг, нужен отладочный вывод; ему же в продакшене нужны только ошибки.
- **Приёмник, который можно сменить потом.** Точка вызова говорит,
  **что** произошло; куда это пойдёт, решает паблишер. Сегодня консоль,
  завтра файл или сервис аналитики, при необходимости и то и другое
  сразу — и ни одна точка вызова не меняется.
- **То, что можно отдать своим пользователям.** Пакет, построенный на
  `if (logging) print(...)`, не даёт пользователям ничего: они не могут
  ни включить его логи, ни отформатировать их, ни влить в собственный
  поток логов. См.
  [logger_builder в вашем собственном пакете](#logger_builder-в-вашем-собственном-пакете).

И ничто из этого не оплачивается, пока логирование выключено:
выключенный уровень — это один вызов пустой функции, а под `assert` или
константой вызов исчезает совсем.

Так что выбор тут не «или — или». Используйте `assert(log.d(...))` для
того, чего не должно остаться в релизных сборках, и уровни с паблишерами
для того, что должно переключаться на ходу.


## Как сделать свой логгер?

Чтобы собрать базовый свой логгер, нужно определить сигнатуру функции
логирования, полезную нагрузку записи лога, уровневый логгер и главный
логгер-менеджер.

Вот упрощённый пример того, как построить логгер строго под нужды вашего
приложения:

**1. Определите сигнатуру функции логирования**

```dart
import 'package:logger_builder/logger_builder.dart';

typedef LogFn =
    bool Function(Object? message, {Object? error, StackTrace? stackTrace});
```

В качестве возвращаемого значения можно выбрать `void`, но если вы
хотите использовать логгер вместе с `assert`, лучше выбрать `bool`. Если
ещё не решили — определённо выбирайте `bool`.

Обратите внимание, что тип `message` — это `Object?`. Во-первых, так
сделано, чтобы в логгер можно было передать любой объект: логгер сам
преобразует его в строку. Во-вторых, это даёт возможность пользоваться
отложенными вычислениями — передать в логгер функцию, которая будет
вызвана, только если лог действительно выводится.

**2. Определите полезную нагрузку записи**

```dart
final class Log extends CustomLog {
  final LazyString _lazyMessage;

  Log(
    super.levelLogger, {
    required Object? message,
    super.error,
    super.stackTrace,
    super.zone,
  }) : _lazyMessage = LazyString(message);

  /// Копия — не новое событие лога: `CustomLog.copy` сохраняет уровень
  /// и зону, а ваш конструктор копии переносит ваши собственные поля —
  /// как это делают две строки ниже. Трансформерам это необходимо.
  Log.copy(Log original, {Object? message})
      : _lazyMessage =
            message != null ? LazyString(message) : original._lazyMessage,
        super.copy(
          original,
          error: original.error,
          stackTrace: original.stackTrace,
        );

  String get message => _lazyMessage.value;
}
```

Это структура, которая будет хранить всю информацию о конкретном логе —
полученную из функции `LogFn` или вычисленную самостоятельно.

Конструктор всегда требует ссылку на `levelLogger` (о нём ниже). Но на
самом деле ссылка на `levelLogger` нужна только для того, чтобы вытащить
из него данные об уровне: `level`, `levelName`, `shortLevelName`. Сама
ссылка не сохраняется.

Кроме того, в базовом классе `CustomLog` уже есть готовые поля `error`
и `stackTrace`. Заполнять их не обязательно, но вы можете ими
пользоваться, если этого требует ваша система логирования. `stackTrace`
можно использовать независимо от `error`. Но если `stackTrace` вы не
передали, а в качестве `error` передали `Error`, а не `Exception`, то
`stackTrace` будет взят из `error` автоматически — если он там есть:

```dart
stackTrace ??= error is Error ? error.stackTrace : null;
```

Ещё у `CustomLog` есть готовое поле `zone`. По умолчанию оно равно
`Zone.current`, то есть зоне, в которой был вызван логгер.

**3. Определите уровневый логгер (логику для конкретного уровня)**

```dart
final class LevelLogger extends CustomLevelLogger<Logger, LevelLogger, LogFn, Log> {
  LevelLogger({
    required super.level,
    required super.name,
    super.shortName,
  }) : super(
         noLog: (_, {error, stackTrace}) => true,
       );

  @override
  LogFn get processLog => (message, {error, stackTrace}) {
      publishLog(
        Log(
          this,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );

      return true;
    };
}
```

При наследовании от класса `CustomLevelLogger` ему нужно передать
несколько типов:

- `Logger` — тип главного логгера
- `LevelLogger` — тип уровневого логгера
- `LogFn` — тип функции логирования
- `Log` — тип события лога

Конструктор класса `CustomLevelLogger` принимает несколько параметров:

- `level` — уровень лога. Это целое число. Чем больше число, тем выше
  уровень лога. В качестве значений можно использовать готовые
  константы из класса `Levels`. Среди них есть и те, что используются
  в `developer.log` и в пакете `logging`: `finest`, `finer`, `fine`,
  `config`, `info`, `warning`, `severe`, `shout`. Но есть и
  дополнительные: `trace`, `verbose`, `debug`, `error`, `critical`.
  В любом случае это просто числа: больше 0 (`Levels.all`) и меньше 2000
  (`Levels.off`). Можно использовать и свои значения.

- `name` — имя уровня лога. Это строковое значение, которое вы можете
  использовать при выводе лога. Параметр обязательный, хотя пользоваться
  им и не обязательно. В структуре `CustomLog` это значение хранится под
  именем `levelName`.

- `shortName` — короткое имя уровня лога. Необязательный параметр. Если
  он не указан, в качестве `shortName` будет использован первый символ
  `name`. В структуре `CustomLog` это значение хранится под именем
  `shortLevelName`. Используйте его как хотите.

- `noLog` — no-op-функция, которая будет вызываться, когда этот уровень
  логирования выключен. Раз сигнатуру функции логирования вы определяете
  сами, то и эту no-op-функцию придётся определить самому. То есть её
  тип должен в точности совпадать с типом `LogFn`. Передавайте сюда
  глобальную функцию или статический метод:

  ```dart
  noLog: _noLog,

  ...

  static bool _noLog(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) => true;
  ```

  Или пустое замыкание:

  ```dart
  noLog: (_, {error, stackTrace}) => true,
  ```

  Производительность в обоих случаях будет одинаковой.

- `publisher` — паблишер, который будет вызываться по умолчанию для
  публикации события `Log`. Обычно паблишер занимается форматированием
  и выводом результата. Но он может и передавать лог другим паблишерам
  (`MultiPublisher`) или ставить обработку события в асинхронную очередь
  (`AsyncPublisher`). По умолчанию используется
  `CustomLogPublisher.noOp()`, который не делает ничего.

  ```dart
  final log = Logger()
    ..level = Levels.all
    ..publisher = CustomLogPublisher(
      (log) => print(log.message),
    );
  ```

  или:

  ```dart
  final class DefaultLogPublisher implements CustomLogPublisher<Log> {
    const DefaultLogPublisher();

    @override
    void publish(Log log) {
      print('[${log.shortLevelName}] ${log.message}');
    }
  }

  // ...

  final log = Logger()
    ..level = Levels.all
    ..publisher = const DefaultLogPublisher();
  ```

Наконец, нужно создать главную функцию `processLog`, которая будет
вызываться под капотом вместо `log.info`, `log.error` и прочих.

По техническим причинам `processLog` не может быть просто функцией. Это
геттер типа `LogFn`, который принимает либо функцию, либо замыкание
соответствующего типа. Реализуйте `processLog` так, как считаете
нужным.

Например, через замыкание:

```dart
@override
LogFn get processLog => (message, {error, stackTrace}) {
      publishLog(
        Log(
          this,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );

      return true;
    };
```

Или через метод:

```dart
@override
LogFn get processLog => _processLog;

bool _processLog(Object? message, {Object? error, StackTrace? stackTrace}) {
  final log = Log(this, message: message, error: error, stackTrace: stackTrace);
  publishLog(log);
  return true;
}
```

На практике варианты равноценны, а привычный довод в пользу метода — что
он не создаёт замыкание на каждом вызове — описывает то, чего не
происходит. `processLog` читается один раз на переключение уровня:
включение уровня кладёт его результат в то поле, через которое
диспетчеризуется `log`, поэтому замыкание создаётся при включении уровня,
а не при записи лога. На 1 млн вызовов каждого варианта
([benchmarks.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/benchmarks.dart))
разница укладывается в 2 нс, и кто впереди — зависит от компилятора: AOT
дал 10.25 нс замыканию против 11.12 нс методу при sd 0.05 и 0.07 —
разница настоящая и ничтожная. JIT: 11.75 против 11.99 при sd 0.25 и 0.28
— разницы нет вовсе. Берите тот, который лучше читается.

Внутри `processLog` нужно сделать три вещи:

1. Создать `Log`.
2. Опубликовать `Log` через `publishLog` — защищённый метод, который
   применяет `CustomLogger.transformer` и затем передаёт лог паблишеру.
   Прямой вызов `publisher.publish` трансформер пропускает.
3. Вернуть `true` (если вы решили последовать совету и выбрали `bool`
   в качестве возвращаемого значения).

Всё это придётся сделать самому. Да, создание логгера требует написать
изрядное количество кода. Но это делается один раз, и это будет ВАШ
собственный уникальный логгер.

**4. Определите главный логгер (управляет уровневыми логгерами)**

```dart
final class Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log> {
  Logger();

  @override
  void registerLevels() {
    registerLevel(_debug);
    registerLevel(_info);
    registerLevel(_error);
  }

  final _debug = LevelLogger(level: Levels.debug, name: 'debug');
  final _info = LevelLogger(level: Levels.info, name: 'info');
  final _error = LevelLogger(level: Levels.error, name: 'error');

  LogFn get d => _debug.log;
  LogFn get i => _info.log;
  LogFn get e => _error.log;
}
```

При наследовании от класса `CustomLogger` используются те же типы, что
и при наследовании от `CustomLevelLogger`.

Дальше нужно решить, какие уровни логирования вам нужны, создать
соответствующие уровневые логгеры и зарегистрировать их в методе
`registerLevels` с помощью метода `registerLevel`. Затем через
подходящие геттеры отдать ссылку на геттер `log` соответствующего
логгера. Будьте внимательны и не ошибитесь здесь: не передайте случайно
ссылку на `processLog`! Именно `log` автоматически меняется на `noLog`,
когда логирование на этом уровне выключено, и на `processLog`, когда
включено!

**5. Пользуйтесь логгером**

```dart
void main() {
  final log = Logger()
      ..level = Levels.all
      ..publisher = const DefaultLogPublisher();

  log.i('Hello, world!');
  log.e('Something went wrong', error: Exception('Something went wrong'));
}
```

Пример целиком можно посмотреть здесь: [simple_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/simple_logger.dart).


## Отложенные вычисления

Когда методу логирования нужно передать потенциально дорогую полезную
нагрузку, используйте замыкания. Запись лога развернёт замыкание лениво,
через `Lazy` и `LazyString`, — только если соответствующий уровень
включён и лог выводится.

```dart
// Замыкание выполнится, только если уровень 'info' сейчас включён
log.info(() => jsonEncode(hugeObject));
```

Рекомендую использовать замыкания во всех случаях, когда вы передаёте
что-то кроме готовых значений, даже если это простая строка с мелкой
интерполяцией или что-то вроде `i++`. Окупается это асимметрией: при
включённом уровне три формы неразличимы — 128.9, 126.8 и 128.4 нс при sd
до 2, — а при выключенном замыкание превращает 36 нс в 3.6 нс. Ничего
измеримого, когда вы проигрываете, и порядок величины, когда выигрываете.

Тер-офф уже существующей функции дешевле ещё: `log.d(buildMessage)` не
аллоцирует ничего на вызов и даёт 1.89 нс на выключенном уровне против
3.57 нс у `log.d(() => ...)`, который создаёт по замыканию на каждый
вызов — независимо от того, включён уровень или нет. Оба варианта далеко
ниже 36 нс жадной сборки строки. (Медиана десяти прогонов по 1 млн вызовов
каждого варианта, AOT, на одной машине; у JIT числа другие по масштабу, но
не по картине. Бенчмарк печатает min, max, mean и sd рядом с каждым
результатом — не верьте разнице, меньшей, чем стоящий рядом sd, включая
процитированные здесь.)

Главный класс для отложенных вычислений — `Lazy`:

```dart
final lazy = Lazy(() => expensiveComputation());
print(lazy.resolved); // expensiveComputation() будет вызвана только здесь
print(lazy.resolved); // expensiveComputation() больше не вызовется
```

`Lazy` возвращает `Object?`. Для типизированного значения наследуйтесь
от класса `TypedLazy`:

```dart
final class LazyString extends TypedLazy<String> {
  final String fallbackValue;

  LazyString(super.unresolved, [this.fallbackValue = 'null']);

  @override
  String convert(Object? resolved) => resolved?.toString() ?? fallbackValue;
}
```

Функция `convert` будет вызвана только для значений, тип которых не
совпал с указанным. Поэтому, если вы ждёте конкретный тип и
преобразование из других типов невозможно, бросайте исключение или
возвращайте запасное значение.

Для `String` есть готовые классы `LazyString` и `LazyStringOrNull`. Если
тип значения не совпадает со `String`, будет вызван метод `toString()`.


## Свои паблишеры

Во время работы программы паблишеры можно подменять — как у логгера
целиком, так и у отдельного уровня:

```dart
import 'package:ansi_escape_codes/style.dart';

//...

final class DefaultLogPublisher implements CustomLogPublisher<Log> {
  const DefaultLogPublisher();

  static String format(Log log) =>
      '[${log.shortLevelName}] ${DateTime.now()} | ${log.message}';

  static void output(String out) => print(out);

  @override
  void publish(Log log) {
    output(format(log));
  }
}

//...

final log = Logger()
  ..level = Levels.all
  // Меняем паблишер глобально
  ..publisher = const DefaultLogPublisher()
  // Меняем паблишер только для ошибок (например, печать красным через ansi)
  ..[Levels.error].publisher = CustomLogFormatter(
    format: DefaultLogPublisher.format,
    output: (str) => print(Styles.red(str)),
  );
```

`CustomLogFormatter` выше — второй, более короткий путь: это
`CustomLogPublisher`, который делит работу надвое — `format` превращает
`Log` в объект `Out`, `output` решает, что с ним делать. Класс вроде
`DefaultLogPublisher` даёт имя и место для состояния; `CustomLogFormatter`
избавляет от класса, когда всё, что нужно, — переиспользовать один
`format` с другим `output`, а это ровно то, что здесь делает уровень
ошибок.


## Асинхронные паблишеры

`CustomLogger` не поддерживает асинхронную обработку логов
самостоятельно. Разумеется, в качестве паблишера можно указать
асинхронную функцию:

```dart
log.publisher = CustomLogPublisher((log) async {
  await ...
});
```

Но логи будут выводиться параллельно, не дожидаясь друг друга. В
некоторых случаях именно это вам и нужно. Но если порядок обработки
логов для вас важен (например, при записи в файл), то этот вариант не
подходит.

Поэтому для асинхронной обработки логов `log.publisher` должен
внутренним образом регистрировать события и выстраивать их
последовательно.

В `logger_builder` уже есть набор готовых асинхронных паблишеров.


### `AsyncPublisher`

`AsyncPublisher` — простой вариант асинхронного обработчика.

```dart
Future<void> main() async {
  final asyncPublisher = AsyncPublisher<Log>((log) async {
    await ...;
  });
  final log = Logger()
    ..level = Levels.all
    ..publisher = asyncPublisher;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPublisher.flush();
}
```

Смотрите пример:
[async_publisher.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher.dart).

### `AsyncPublisherBase`

`AsyncPublisherBase` позволяет создать собственный класс обработчика.

```dart
final class MyAsyncPublisher extends AsyncPublisherBase<Log> {
  @override
  FutureOr<void> handle(Log log) async {
    await ...;
  }
}

Future<void> main() async {
  final asyncPublisher = MyAsyncPublisher();
  final log = Logger()
    ..level = Levels.all
    ..publisher = asyncPublisher;

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');

  await asyncPublisher.flush();
}
```

Смотрите также пример:
[async_publisher.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher.dart).

> [!NOTE]
> У всех вариантов обработчиков есть версия `Base`.

### `AsyncPublisherWithParam`

`AsyncPublisherWithParam` позволяет добавить обработчику дополнительный
параметр.

```dart
Future<void> main() async {
  final asyncPublisher =
      AsyncPublisherWithParam<bool, Log>((sendToAnalytics, log) async {
    print(log.message);
    if (sendToAnalytics) {
      await ...;
    }
  });
  final log = Logger()
    ..level = Levels.all
    ..publisher = asyncPublisher.withParam(false)
    ..[Levels.error].publisher = asyncPublisher.withParam(true);

  log.d('Debug message');
  log.i('Info message');
  log.e('Error message');
}
```

Смотрите также пример:
[async_publisher_with_param.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_param.dart).

### `AsyncPublisherWithBuffer`

```dart
Future<void> main() async {
  final asyncPublisher = AsyncPublisherWithBuffer<Log>((logs, retryBuffer) async {
    try {
      await ...;
    } catch (e) {
      retryBuffer.addAll(logs); // Неудачные логи обрабатываются автоматически
    }
  });

  final log = Logger()
    ..level = Levels.all
    ..publisher = asyncPublisher;

  log.d('1 Debug message');
  log.i('1 Info message');
  log.e('1 Error message');

  await null; // обработано 3 сообщения

  log.d('2 Debug message');
  log.i('2 Info message');
  log.e('2 Error message');

  log.d('3 Debug message');
  log.i('3 Info message');
  log.e('3 Error message');

  await null; // обработано 6 сообщений

  await asyncPublisher.flush();
}
```

Смотрите также пример:
[async_publisher_with_buffer.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer.dart).

### Полный набор

Две независимые оси — нужен ли обработчику дополнительный параметр и
работает ли он пачками — дают четыре базовых класса, и каждый есть
в разновидности «делай всё сам» и «форматирование + вывод»:

|                          | по одному логу за раз                                 | пачками                                                                |
| ------------------------ | ----------------------------------------------------- | ---------------------------------------------------------------------- |
| **без параметра**        | `AsyncPublisher` / `AsyncFormatter`                   | `AsyncPublisherWithBuffer` / `AsyncFormatterWithBuffer`                 |
| **с параметром**         | `AsyncPublisherWithParam` / `AsyncFormatterWithParam` | `AsyncPublisherWithBufferAndParam` / `AsyncFormatterWithBufferAndParam` |

Половина `Async*Publisher*` берёт один колбэк `handle` и всё делает
в нём. Половина `AsyncFormatter*` делит это надвое: `format` превращает
лог (или пачку) в объект `Out`, `output` отправляет этот объект
куда-то — и это то, что нужно, когда одна и та же нагрузка идёт
в несколько мест или когда дорогая часть — именно форматирование:

```dart
final asyncFormatter = AsyncFormatter<Log, Map<String, Object?>>(
  format: (log) async => {'level': log.levelName, 'message': log.message},
  output: (out) async => apiClient.post('/logs', data: out),
);
```

Все восемь принимают одни и те же четыре необязательных аргумента:

- **`onError`** — вызывается, когда обработчик бросает исключение. Без
  него ошибка уходит в текущую зону, а в обычной Dart-программе без
  error-зоны непойманная асинхронная ошибка **завершает изолят**, после
  чего ваши логи обрабатывать уже некому. Задайте его — или оберните
  приложение в `runZonedGuarded`;
- **`sync`** — доставляет ли внутренний `StreamController` синхронно. Не
  трогайте, если точно не знаете, что вам это нужно;
- **`maxQueueSize`** — сколько записей очередь принимает, прежде чем
  начнёт отказывать. Считается принятое и ещё не обработанное: то, что
  ждёт в очереди, плюс запись (или пачка), которую обрабатывают прямо
  сейчас. Умолчание — 10 000. На пределе отказ получает **входящий**
  лог: он уходит в `onDropped` и в очередь не попадает, поэтому всё уже
  принятое всё равно будет доставлено, а `flush()` и `close()` значат
  ровно то же, что и раньше. Очередь разбирается только на обороте цикла
  событий, поэтому плотный цикл, публикующий больше границы и ничего не
  ожидающий, теряет остаток при сколь угодно живом стоке — первым это
  заметил собственный бенчмарк пакета, который публикует 20 000 логов
  ровно таким циклом. `null` — сознательный отказ от границы:
  очередь тогда растёт, пока процессу не кончится память, и это верная
  сделка, только если вход вы ограничиваете сами, а потерять лог хуже,
  чем умереть;
- **`onDropped`** — вызывается с тем, что отброшено. У всех восьми это
  лог, которому отказала полная очередь; у четырёх буферизованных ещё
  и пачка, исчерпавшая бюджет `maxRetries`, и записи, возвращённые
  в `retryBuffer` уже после вызова `close()`, — обработать их некогда.
  Оставить его пустым — не значит спрятать потерю: паблишер скажет о ней
  сам, напечатав первую сразу и сосчитав остальные в сводку не чаще раза
  в пять секунд — с расширением до минуты, пока потери идут.
  `onDropped: (_) {}` это заглушает. Небуферизованные четыре отдают по
  одному логу за раз (и `param` вместе с ним, где он есть),
  буферизованные — списком.

У четырёх буферизованных есть ещё два:

- **`retryDelay`** — сколько ждать перед повторной попыткой для пачки,
  возвращённой через `retryBuffer`. Умолчание `Duration.zero` всё равно
  проходит через цикл событий, поэтому мёртвый приёмник не может
  заморить голодом таймеры или ваш же `close()`, но повтор идёт так
  быстро, как позволяет цикл. Задайте настоящую задержку, если приёмник
  может быть недоступен какое-то время; она удваивается с каждой
  попыткой, с потолком в 32 базовых. `close()` ничего из этого не
  выжидает — он гасит взведённый таймер и делает одну немедленную
  последнюю попытку;
- **`maxRetries`** — сколько раз пачка, возвращённая через `retryBuffer`,
  повторяется, прежде чем её отбросят. Умолчание — 100. Считается
  *серия* неудач: пачка, которая прошла, возвращает весь бюджет, и
  оживший приёмник получает полный запас заново. Ноль отбрасывает
  возвращённую пачку сразу, а безграничного значения нет намеренно.
  Вечный повтор не доставляет пачку, падающую детерминированно
  (бросающий `toString`, несериализуемое значение), и не отбрасывает её
  тоже — он занимает ядро, топит `onError` и держит взведённый таймер,
  чего само по себе достаточно, чтобы воркер никогда не завершился.

Классы `Base` (`AsyncPublisherBase` и прочие) — на случай, когда вместо
колбэка вам нужен именованный класс с собственным состоянием;
`isClosed` говорит, был ли вызван `close()`.

`flush()` завершается, когда обработано всё принятое к этому моменту,
а `close()` перед завершением дренирует очередь. `flush()`, вызванный,
пока `close()` ещё дренирует, отдаёт именно это закрытие, а не уже
завершённый future — одинаково у всех восьми и у обеих обёрток, так что
шатдаун, ожидающий флэша, не услышит «очередь пуста», пока она не пуста.

> [!IMPORTANT]
> Все эти очереди **ограниченны**: `maxQueueSize` по умолчанию — 10 000
> записей, принятых и ещё не обработанных. Дальше входящий лог получает
> отказ и уходит в `onDropped` — задайте его, чтобы сохранить эти логи,
> иначе паблишер хотя бы скажет, сколько их потерял. Ничего уже принятого не теряется, поэтому
> `flush()` и `close()` значат прежнее. `maxQueueSize: null` снимает
> границу и позволяет логам копиться, пока процессу не кончится память;
> это верная сделка, только если вход вы ограничиваете сами.
>
> В буферизованных вариантах `retryBuffer` — единственное, что сохраняет
> лог при сбое: бросивший обработчик теряет всё, что не вернул в буфер.


## Несколько паблишеров

Вспомогательный класс `MultiPublisher` позволяет отправить лог
нескольким паблишерам.

```dart
// `<Log>` обязателен во всех трёх местах. У паблишера, лежащего
// в локальной переменной, нет контекстного типа, из которого можно было бы
// вывести `Log`, — он станет `CustomLog`, и присваивание в `log.publisher`
// не скомпилируется.
final consolePrinter = CustomLogPublisher<Log>((log) => print('Console: $log'));
final filePrinter = AsyncPublisher<Log>((log) async {/* пишем в файл */});

final multiPublisher = MultiPublisher<Log>([
  consolePrinter,
  filePrinter,
]);

log.publisher = multiPublisher;

// ...

await multiPublisher.flush();
```

Исключение, брошенное одним паблишером, не прерывает публикацию:
остальные паблишеры лог всё равно получат. Передайте `onError`, чтобы
обрабатывать такие ошибки самостоятельно, — он получает и сбойный
паблишер, и ошибку:

```dart
final multiPublisher = MultiPublisher<Log>(
  [consolePrinter, filePrinter],
  onError: (publisher, error, stackTrace) =>
      print('$publisher failed: $error'),
);
```

Без `onError` ошибка сообщается в текущую зону как непойманная
асинхронная ошибка (во Flutter она попадает в
`PlatformDispatcher.onError`, внутри `runZonedGuarded` — в его
обработчик). Учтите, что обычная Dart-программа без error-зоны на таких
ошибках по умолчанию завершает изолят.

`flush()` и `close()` расходятся только по тем паблишерам, которые
вообще можно сбросить и закрыть, — по реализующим `Flushable`
и `Closable`. Все асинхронные паблишеры их реализуют, включая адаптер,
возвращаемый `withParam()`; у обычного `CustomLogPublisher` сбрасывать
нечего, и он пропускается.

Смотрите также пример:
[multi_publisher.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/multi_publisher.dart).


## Иерархические логгеры

Саблогер создаётся через защищённый конструктор `CustomLogger.sub`.
Раз он защищённый, вы открываете его так, как удобно вашему логгеру, —
обычно именованным конструктором плюс методом, который хорошо читается
в точке вызова:

```dart
final class Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log> {
  final String name;

  Logger(this.name);

  Logger._sub(Logger parent, this.name) : super.sub(parent);

  Logger child(String name) => Logger._sub(this, '${this.name}.$name');

  // registerLevels(), геттеры, ... как и раньше
}
```

```dart
final root = Logger('app')
  ..level = Levels.info
  ..publisher = const DefaultLogPublisher();

final db = root.child('db');       // наследует уровень и паблишер
final http = root.child('http');
```

**Что наследуется.** Три вещи копированием — `level`, поуровневые
паблишеры и `transformer` — и `onError` поиском. У каждой из трёх своя
связь, а у паблишеров есть ещё одна ручка —
пин на уровне, поверх связи логгера. Изменение у родителя доходит до
каждого саблогера, у которого соответствующая связь ещё цела, и там — до
каждого уровня, на котором нет своего пина:

```dart
root.level = Levels.debug; // db и http тоже переключаются на debug
```

`onError` стоит особняком. Он разрешается по цепочке родителей в тот
момент, когда нужен, а не копируется вниз, поэтому саблогер без своего
обработчика пользуется родительским. Флага связи у него нет, `relink()`
его не трогает, а присваивание `null` возвращает унаследованный
обработчик, а не отвязывает, — см.
[Ошибки на пути публикации](#ошибки-на-пути-публикации).

**Как саблогер отвязывается.** Присваивание `level`, общего `publisher`
или `transformer` прямо на саблогере рвёт эту связь — с этого момента
саблогер держит своё значение и родителя игнорирует:

```dart
http.level = Levels.all;   // http теперь сам по себе, db по-прежнему за root
root.level = Levels.error; // db → error, http остаётся на all
```

Паблишер, присвоенный одному уровню, — исключение: он связь не рвёт,
а ставит пин на этот уровень. Остальные уровни этого саблогера
по-прежнему следуют за родителем, `publisherLinked` остаётся `true`,
а снимается пин тоже по уровню — см. **Как привязаться обратно** ниже.

Присваивание того же самого значения — идиома отвязки без изменения
чего бы то ни было: `child.level = child.level` и `child.transformer =
child.transformer`. У паблишеров эта идиома тоже поуровневая
(`child[Levels.info].publisher = child[Levels.info].publisher` ставит
пин, ничего не меняя); идиомы, чтобы отвязать разом все паблишеры без
изменения значений, больше нет — присвойте общий паблишер или
пройдитесь циклом по `levels`.

**Как привязаться обратно.** `relink()` заново наследует все три вещи от
родителя и включает распространение изменений. Заодно он снимает все
поуровневые пины, так что логгер целиком снова следует за родителем.
`false` он возвращает только для корневого логгера:

```dart
http.relink(); // снова следует за root, вместе с пинами
```

`CustomLevelLogger.relink()` — то же самое, но уже: вызванный у уровня,
он снимает пин только с него и остального логгера не трогает. Он ничего
не возвращает, в отличие от `relink()` логгера, — над уровнем всегда
что-то есть, в худшем случае его собственный логгер:

```dart
http[Levels.info].relink(); // в цепочку возвращается только этот уровень
```

Когда сверху брать нечего — логгер настроен только пер-уровнево, общего
паблишера нет нигде по цепочке, — уровень возвращается к no-op-паблишеру
и `hasPublisher` становится `false`, а не сохраняет то, что у него
случайно оказалось. `CustomLogger.relink()` применяет то же правило
к каждому уровню, с которого снимает пин.

Родитель держит своих саблогеров через слабые ссылки, поэтому саблогеры
никогда не нужно освобождать — брошенная ветка собирается целиком.
Саблогер, наоборот, держит родителя сильной ссылкой, так что логгер,
который вы храните, никогда не теряет цепочку, от которой наследуется.

Саблогер не обязан регистрировать те же уровни, что и родитель.
Поуровневый паблишер для уровня, которого у саблогера нет, молча
пропускается; обращение к незарегистрированному уровню через
`operator []` бросает `StateError`.

Смотрите также пример:
[hierarchical_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/hierarchical_logger.dart).


## Трансформеры

Трансформер выполняется для каждого лога прямо перед передачей его
паблишеру. Если он возвращает лог, публикуется этот лог вместо
исходного; если возвращает `null`, лог отбрасывается целиком.
Существует он в основном ради безопасности — маскировать секреты
и персональные данные до того, как они куда-либо попадут:

```dart
final log = Logger('app')
  ..level = Levels.all
  ..publisher = const DefaultLogPublisher()
  ..transformer = (log) {
    final message = log.message;

    return message.contains('token=')
        ? Log.copy(
            log,
            message: message.replaceAll(RegExp(r'token=\S+'), 'token=***'),
          )
        : log;
  };

log.i('GET /api?token=abcdef'); // [i] GET /api?token=***
```

Трансформеры наследуются саблогерами и подчиняются тем же правилам
связи, что уровень и паблишеры (см. выше).

**Fail-closed.** Если трансформер бросает исключение, лог **не**
публикуется — непреобразованный лог наружу не утекает, — а ошибка уходит
в текущую зону.

**На отдельный приёмник: `TransformPublisher`.**
`CustomLogger.transformer` применяется ко всему, что логгер публикует.
Чтобы маскировать только для одного приёмника, оберните этот приёмник:

```dart
log.publisher = MultiPublisher([
  consolePrinter,                                   // как есть
  TransformPublisher(fileStorage, transformer: redact), // с маскировкой
]);
```

У `TransformPublisher` есть собственный `onError`, и он покрывает обе
половины работы: и бросивший `transformer`, и бросивший обёрнутый
паблишер. Без обработчика эти две расходятся — ошибка трансформера
уходит в текущую зону, а ошибка обёрнутого паблишера продолжает путь
в место вызова лога, ровно как и без обёртки. `flush` и `close`
делегируются обёрнутому паблишеру, если он их поддерживает; `close`
терминален в любом случае.

> [!WARNING]
> Трансформер не должен логировать через свой же логгер, и паблишер
> тоже: вложенный вызов вернётся прямо сюда же и будет рекурсировать,
> пока не кончится стек. Оба цикла отлавливаются — вложенный лог
> отбрасывается, а о ситуации сообщается через `StateError`. Считайте
> это страховкой от неуправляемой рекурсии, а не способом логировать из
> трансформера.
>
> Страховка синхронная, и на деле это две страховки с разным охватом.
> Половина про трансформер — своя у каждого логгера: она ловит любой
> цикл, вернувшийся, пока работает трансформер этого логгера, через
> сколько угодно уровней и логгеров. Половина про публикацию — своя
> у каждого **уровневого** логгера, поэтому паблишер, логирующий
> в *другой* уровень того же логгера, разрешён, а цикл всё равно
> сработает в тот момент, когда вернётся на уровень, чей паблишер сейчас
> работает.
>
> Ни одна из половин не ловит цикл через **саблогер**, унаследовавший тот
> же трансформер (саблогер — отдельный логгер со своей страховкой), и ни
> одна не переживает **асинхронного скачка**: трансформер, откладывающий
> вложенный лог через `scheduleMicrotask` или `Future`, оказывается вне
> страховки целиком, и безусловный вариант будет крутиться вечно. То же
> и с асинхронным паблишером, чей `handle` идёт много позже возврата из
> `publish`.


### Ошибки на пути публикации

`CustomLogger.onError` — единственное место, куда стекается всякая
ошибка, которую логгер ловит по дороге к паблишеру: бросивший
`transformer`, бросивший паблишер и срабатывание страховки от рекурсии.

```dart
final log = Logger('app')
  ..level = Levels.all
  ..onError = ((error, stackTrace) => report(error, stackTrace))
  ..publisher = const DefaultLogPublisher();
```

Внутри каскада стрелочную функцию заворачивайте в скобки, как
и `transformer`: без них `..` следующей строки разбирается как часть тела
стрелки.

Без обработчика каждый случай сохраняет своё прежнее поведение: ошибка
трансформера и срабатывание страховки уходят в текущую зону, а ошибка
паблишера выходит наружу в место вызова лога. Учтите, что означает путь
через зону в обычной Dart-программе без error-зоны: непойманная
асинхронная ошибка завершает изолят, то есть баг в маскирующем
трансформере кладёт процесс. Задать этот колбэк — и есть способ сделать
так, чтобы логирование перестало быть способно уронить логирующего.

Разрешается он по цепочке родителей, а не копируется вниз, поэтому
саблогер без своего обработчика пользуется родительским.

> [!WARNING]
> Обработчик не должен логировать через логгер, которому принадлежит.
> Обе страховки выше в этот момент ещё взведены, поэтому логирующий
> обработчик возвращается прямо в ту страховку, которая только что
> сработала, а та доложила бы через него снова. Это отлавливается —
> вторая ошибка уходит в текущую зону, а не обратно в обработчик, — но
> вложенный лог при этом отбрасывается, а не публикуется. Хотите, чтобы
> сбой был залогирован, — докладывайте в *другой* логгер, это не
> затронуто.

## Типовые сценарии

Во фрагментах ниже используется логгер, построенный в
[simple_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/simple_logger.dart):
`Log` с полем `message` и `Logger` с методами `d`, `i` и `e`.

### Как писать в stdout и stderr

На нативных платформах `print` всегда пишет в stdout, поэтому вывод
ошибок подмешивается в обычный вывод программы. Дайте уровню ошибок
собственный паблишер:

```dart
import 'dart:io';

String format(Log log) => '[${log.shortLevelName}] ${log.message}';

final log = Logger()
  ..level = Levels.all
  ..publisher = CustomLogFormatter(format: format, output: stdout.writeln)
  ..[Levels.error].publisher =
      CustomLogFormatter(format: format, output: stderr.writeln);
```

> [!NOTE]
> Только для нативных платформ. На web никакого stdout нет: `print` уходит
> в `dartPrint`, если его определил встраивающий код, и в `console.log`
> иначе — один и тот же код и в `dart compile js`, и в `dart compile wasm`.
> `dart:io` там хуже, чем недоступен: импорт компилируется, а `stdout`
> и `stderr` бросают `UnsupportedError` в рантайме. Под Node `console.log`
> действительно попадает в stdout, в браузере — в консоль devtools,
> а `console.error` Dart не вызывает никогда, так что развести на web два
> потока этим способом нельзя вовсе.

### Как писать в файл

Запись в файл асинхронна, и записи не должны перемешиваться, поэтому
берите буферизованный асинхронный паблишер: он собирает логи в пачки
и обрабатывает их по одной.

```dart
import 'dart:io';

final file = File('app.log');

final filePublisher = AsyncPublisherWithBuffer<Log>((logs, retryBuffer) async {
  final batch =
      logs.map((log) => '[${log.shortLevelName}] ${log.message}\n').join();
  try {
    await file.writeAsString(batch, mode: FileMode.append);
  } on Object catch (error) {
    // Сохраняем пачку для следующей попытки, вместо того чтобы потерять её.
    retryBuffer.addAll(logs);
    stderr.writeln('cannot write to ${file.path}: $error');
  }
});

final log = Logger()
  ..level = Levels.all
  ..publisher = filePublisher;
```

Очередь перед файлом по умолчанию держит 10 000 записей: если диск
встанет дольше, чем на них, самые новые логи получат отказ, и увидеть их
можно в `onDropped`. Передайте `maxQueueSize: null`, чтобы очередь вместо
этого росла, пока процесс не умрёт, — см.
[полный набор](#полный-набор) про это, `retryDelay` и остальное.

Перед выходом из программы очередь нужно опустошить, иначе последняя
пачка до диска не доедет:

```dart
await filePublisher.close();
```

`close()` необратим, и «отказывается» — это сильнее, чем звучит: он
обрабатывает всё принятое до сих пор, а **любой последующий
`log.i(...)` бросает `StateError` прямо в точке вызова**. Так сделано
намеренно: закрыть паблишер и продолжать логировать — это ошибка
порядка завершения, и узнать о ней сразу лучше, чем кормить мёртвый
буфер. Но это же значит, что случайная строчка лога в `finally` может
уронить программу. Закрывайте последним — или используйте `flush()`,
когда нужно лишь дождаться опустошения очереди и логировать дальше.

Учтите, что `flush()` означает две разные вещи в зависимости от того,
какой паблишер вы выбрали, и обе полезны:

- **снимок** — `AsyncPublisher`, `AsyncFormatter` и их варианты
  `WithParam` завершаются, когда обработано всё, что стояло в очереди
  **на момент вызова**. Логи, опубликованные после, попадут в следующий
  круг;
- **опустошение** — буферизованные варианты завершаются, когда буфер
  **пуст**, включая логи, опубликованные уже после вызова. При ровном
  потоке логирования flush-опустошение заканчивается позже, чем
  flush-снимок, а на нагруженном логгере может не закончиться вовремя
  вовсе.

`MultiPublisher`, в котором есть и то и другое, смешивает обе гарантии,
так что, когда нужна жёсткая точка «всё вышло», берите `close()`.

### Как добавить отметку времени

Фиксируйте время в логе, а не в форматтере:

```dart
final class Log extends CustomLog {
  final DateTime time;
  final LazyString _lazyMessage;

  Log(
    super.levelLogger, {
    required Object? message,
    super.error,
    super.stackTrace,
  })  : time = DateTime.now(),
        _lazyMessage = LazyString(message);

  String get message => _lazyMessage.value;
}

String format(Log log) =>
    '${log.time} [${log.shortLevelName}] ${log.message}';
```

`DateTime.now()` внутри форматтера говорит правду только для
синхронных паблишеров. Как только вывод становится асинхронным или
буферизованным, форматирование происходит в момент обработки пачки,
а не в момент события, — и все логи пачки получают почти одинаковую
и неверную отметку времени.

### Как раскрасить логи

Цвет — часть форматирования, поэтому его место в паблишере:

```dart
import 'package:ansi_escape_codes/style.dart';

String format(Log log) => '[${log.shortLevelName}] ${log.message}';

final log = Logger()
  ..level = Levels.all
  ..publisher = CustomLogFormatter(format: format, output: print)
  ..[Levels.error].publisher = CustomLogFormatter(
    format: format,
    output: (str) => print(Styles.red(str)),
  );
```

Escape-последовательности нужны терминалу, а не файлу: раскрасив общий
форматтер, вы положите `\x1b[31m` и в файл лога. Когда лог идёт и туда
и туда, дайте каждому приёмнику свой паблишер:

```dart
final log = Logger()
  ..level = Levels.all
  ..publisher = MultiPublisher<Log>([
    // Терминал: с цветом.
    CustomLogFormatter(format: format, output: (str) => print(Styles.red(str))),
    // Файл: обычный текст.
    filePublisher,
  ]);
```


## Типичные ошибки

**Собирать сообщение заранее**

```dart
log.d('Cache state: ${jsonEncode(cache)}'); // ПЛОХО
```

Интерполяция выполняется ещё до того, как `log.d` вообще будет вызван,
поэтому `jsonEncode` отработает независимо от того, включён отладочный
уровень или нет, — ровно та цена, ради избавления от которой этот пакет
и существует. Передайте замыкание, и оно вычислится, только если уровень
включён:

```dart
log.d(() => 'Cache state: ${jsonEncode(cache)}'); // ХОРОШО
```

См. [Отложенные вычисления](#отложенные-вычисления).

**Откладывать то, что никогда не откладывается**

Зеркальное отражение той же ошибки. Замыкание окупается только на
уровне, который действительно может быть выключен: на уровне, который
у вас включён всегда, оно всё равно вычисляется при каждом вызове,
и всё, что оно добавляет, — лишняя аллокация:

```dart
log.i(() => 'User $id logged in'); // бессмысленно, если `i` всегда включён
log.i('User $id logged in');       // просто передайте значение
```

**Отдавать наружу `processLog` вместо `log`**

```dart
LogFn get d => _d.processLog; // ПЛОХО: логирует всегда
LogFn get d => _d.log;        // ХОРОШО: переключается вместе с уровнем
```

`log` — это то поле, которое пакет подменяет между `processLog`
и no-op-функцией. Отдав наружу `processLog` напрямую, вы получаете
уровень, который невозможно выключить, — и ни капли той
производительности, ради которой переключатель и сделан.

**Публиковать через `publisher.publish` вместо `publishLog`**

```dart
@override
LogFn get processLog => (message, {error, stackTrace}) {
      publisher.publish(Log(this, message: message)); // ПЛОХО
      publishLog(Log(this, message: message));        // ХОРОШО
      return true;
    };
```

Именно `publishLog` применяет `CustomLogger.transformer` перед передачей
лога дальше. Обращение напрямую к паблишеру молча его пропускает,
поэтому маскирование и фильтрация не выполняются вовсе.

**Ставить отметку времени в форматтере**

`DateTime.now()` в форматтере — это время, когда лог был **напечатан**,
а оно перестаёт совпадать со временем, когда событие **произошло**, как
только появляется буферизованный или асинхронный паблишер. См.
[Как добавить отметку времени](#как-добавить-отметку-времени).

**Выходить, не опустошив асинхронный паблишер**

```dart
log.i('done');
exit(0); // ПЛОХО: логи из очереди всё ещё в памяти
```

Асинхронные и буферизованные паблишеры обрабатывают логи после возврата
из вызова. Дождитесь `flush()` или `close()` перед завершением
программы.

**Логировать изнутри трансформера**

```dart
log.transformer = (entry) {
  log.d('masking $entry'); // ПЛОХО: заново входит в трансформер
  return mask(entry);
};
```

Вложенный вызов запускает трансформер снова, и снова. Такой вызов
отлавливается и отбрасывается с `StateError`, но лог, который вы хотели
записать, теряется — собирайте нужное в обычный список или пользуйтесь
логгером, до которого этот трансформер не достаёт.


## logger_builder в вашем собственном пакете

Пакет, который логирует через `print`, не даёт своим пользователям
ничего: они не могут ни включить вывод, ни изменить его вид, ни
направить его куда-либо. Открытый логгер стоит вам одного публичного
поля и даёт им все три возможности.

**Откройте логгер и оставьте его выключенным**

```dart
// lib/src/log.dart
final packageLog = Logger('my_package');
```

Свежепостроенный логгер стоит на `Levels.off`, поэтому пользователь,
который его не трогал, вашего вывода никогда не увидит, — так и ведёт
себя вежливая зависимость. Логируйте внутри своего пакета свободно:
ничего не публикуется, пока об этом не попросят.

**Пусть пользователь решает всё про вывод сам**

```dart
// Приложение пользователя:
import 'package:my_package/my_package.dart';

void main() {
  packageLog
    ..level = Levels.info
    ..publisher = myAppPublisher; // его формат, его приёмник
}
```

Не устанавливайте паблишер сами, не оборачивайте ничего
в `runZonedGuarded` за пользователя и не решайте, что ошибкам место
в stderr. Это решения приложения, и, принимая их за него, вы делаете
свои логи инородным телом в чужом потоке логов вместо его части.

**Отдайте пользователю и иерархию**

Саблогеры наследуют уровень и паблишер от родителя, поэтому одно
присваивание настраивает весь ваш пакет — а пользователь, которому нужен
только ваш HTTP-слой, всё ещё может это сказать:

```dart
final httpLog = packageLog.child('http');
final cacheLog = packageLog.child('cache');

// В приложении: всё на уровне warning, HTTP-слой целиком.
packageLog.level = Levels.warning;
httpLog.level = Levels.all;
```

**Помните, что ваш тип `Log` — это публичный API**

Пользователи пишут форматтеры под него, поэтому его поля — часть
контракта вашего пакета: добавить поле безопасно, переименовать или
убрать — ломающее изменение. Держите этот тип экспортированным
и задокументированным.


## Примеры

В каталоге [example/logger_builder_examples](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/) лежат более развёрнутые примеры, показывающие:

### Логгеры

- Простой логгер
  ([логгер](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/simple_logger.dart),
  [использование](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/simple_logger.dart)).
- Методы логирования с несколькими параметрами
  ([логгер](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/complex_logger.dart),
  [использование](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/complex_logger.dart)).
- Логгеры со сложной иерархией
  ([логгер](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/hierarchical_logger.dart),
  [использование](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/hierarchical_logger.dart)).
- Свои форматтеры, превращающие лог прямо в json-словари
  ([логгер](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/json_reporter.dart),
  [использование](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/json_reporter.dart)).

### Асинхронные паблишеры

- Асинхронный паблишер
  ([паблишер](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher.dart),
  [пример](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher.dart))
- Асинхронный паблишер с параметром
  ([паблишер](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher_with_param.dart),
  [пример](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_param.dart))
- Асинхронный паблишер с буфером
  ([паблишер](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher_with_buffer.dart),
  [пример](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer.dart))
- Асинхронный паблишер с буфером и параметром
  ([паблишер](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher_with_buffer_and_param.dart),
  [пример](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer_and_param.dart))
- Мульти-паблишер
  ([паблишер](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/multi_publisher.dart),
  [пример](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/multi_publisher.dart))
