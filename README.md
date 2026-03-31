[![Dart CI](https://github.com/vi-k/logger_builder/actions/workflows/dart.yml/badge.svg)](https://github.com/vi-k/logger_builder/actions/workflows/dart.yml)
[![Pub Publisher](https://img.shields.io/pub/publisher/logger_builder)](https://pub.dev/publishers/yet-another.dev/packages)
![Pub Version](https://img.shields.io/pub/v/logger_builder)
![GitHub License](https://img.shields.io/github/license/vi-k/logger_builder)

A toolkit for creating your own customizable and hierarchical loggers in Dart
with good performance when disabled.

## Features

- **Custom Loggers**: Build your own logger classes extending `CustomLogger`
  with tailored log methods, entries, and customizable properties.
- **Hierarchical Loggers**: Inbuilt support for hierarchical structures where
  subloggers inherit capabilities (levels, publishers) from parents,
  with the flexibility to override them.
- **Lazy Evaluation**: Includes utilities like `Lazy` and `LazyString` to avoid
  expensive operations (like string interpolations or JSON encoding) when
  a logging level is disabled.
- **Async & Buffered Publishers**: Base classes like `AsyncPublisher` for
  printing logs asynchronously or buffering them before sending (e.g., to an
  analytics service).
- **Flexible Formatting & Output**: Loggers decouple the **format** step (which
  formats the entry into a string or other object) and the **output** step
  (which decides what to do with the formatted object, like printing to the
  console).


## Table of contents

- [What can this toolkit do?](#what-can-this-toolkit-do)
- [Performance](#performance)
- [How to make your own logger?](#how-to-make-your-own-logger)
- [Lazy Evaluation](#lazy-evaluation)
- [Custom Publishers](#custom-publishers)
- [Async Publishers](#async-publishers)
- [Several Publishers](#several-publishers)
- [Examples](#examples)

## What can this toolkit do?

Next, there will be examples of logger implementations: what can be done. How
to do them will be explained below.

**Custom logging methods**

You yourself determine which logging methods your logger will have.

For example, like this:

```dart
final log = Logger();
log.info('Hello');
log.error('Error', error: Exception('Test'));
```

Or like this:

```dart
final log = Logger();
log.v('Verbose info');
log.d('Debug info');
log.w('Warning info');
log.e('Error', error: Exception('Test'));
log.f('Fatal error', error: Exception('Test'));
```

**Any parameters you need**

For example, like this:

```dart
final log = Logger();
log.i('MyClass', 'Info message');
```

Or like this:

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

**Hierarchical loggers**

You can create nested loggers associated with the main one. In this case,
nested loggers do not need to be disposed of: when they leave the scope, they
are automatically removed from the main logger. Therefore, you can safely
create them in each function or unit where needed.

```dart
final log = Logger('app');
final authLog = log.withAddedName('auth');
final loginLog = authLog.withAddedName('login');
final logoutLog = authLog.withAddedName('logout');

log.i('App started');                     // app | App started
authLog.i('Check user authentification'); // app | auth | Check user authentification
loginLog.i('User login');                 // app | auth | login | User login
logoutLog.i('User logout');               // app | auth | logout | User logout
```

See example: [hierarchical_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/hierarchical_logger.dart).

**Any output type**

The output type does not necessarily have to be a `String`. It can be, for
example, ready-made json or a type prepared for conversion to json:

```dart
final log = Logger();
log.i('event', 'Hello', data: {'a': 1});
// {"level":"info","name":"event","message":"Hello","data":{"a":1}}
```

See example: [json_reporter.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/json_reporter.dart).

**Customizable formatting**

```dart
final log = Logger();
log.publisher = CustomLogPublisher(
  (log) {
    print('[${log.shortLevelName}] ${log.message}');
  },
);
```

Formatting is available not only at the stage of creating a logger class, but
also later, in real time. This allows you to create loggers for packages: you
create a package and logging in it, which will be useful not only to you as
the package developer, but also to its users. And you give the user not only
access to the logs, but also the ability to configure the output format so that
YOUR logs become an integral part of the USER's logs in the form in which they
want to see them.

```dart
final log = Logger('package');
// Your logs:
log.i('feature', 'Info message');
// [i] package | feature | Info message

// User logs after configuration as an example:
log.publisher = ...;
// 2026-02-23 19:19:09.123 [INFO] package/feature/ Info message
```

**Customizable output**

Formatting and output can be separated so that different formatting can be
configured for different logging levels, but with a single output:

```dart
import 'package:ansi_escape_codes/style.dart';

String format(Log log) => '[${log.shortLevelName}] ${log.message}';

final log = Logger()
  ..publisher = CustomLogFormatter(
    format: format,
    output: print,
  )
  ..[Levels.error].publisher = CustomLogFormatter(
    format: (log) => red(format(log)),
    output: print,
  );
```

Or, conversely, a single formatting, but different outputs for different
levels.

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
    output: (str) => print(red(str)),
  );
```


## Performance

When logging, it is often not so important how much time is spent on logging,
but it is very important how much time logging takes when it is disabled.

**Basic level of logger disabling**

```dart
final log = Logger()..level = Levels.off;
log.d('This will not be logged');
```

If logging is disabled, a no-op function is called under the hood. No
calculations, no checks. Just one call to an empty no-op function, which, as
a rule, is well optimized by the compiler.

**Lazy evaluation of parameters**

However, in normal use, the function parameters will still be evaluated.
Therefore, the package provides utilities for deferred evaluation:

```dart
final log = Logger();
...
log.d(() => expensiveCalculation());
// or:
log.d(expensiveCalculation);
```

**Complete removal of logging code**

For more demanding cases where maximum performance is required, the logger
is designed for convenient use with asserts and constants.

Using asserts is a common life hack for cutting out not only unnecessary checks
from the code, but also logging functions. Usually it looks like this:

```dart
assert(() {
  log.d('Debug info');
  return true;
}());
```

It's quite cumbersome! The package provides the ability to do this:

```dart
assert(log.d('Debug info'));
```

And instead of:

```dart
const logging = bool.fromEnvironment('logging');
if (logging) log.d('Debug info');
```

you can do this:

```dart
logging && log.d('Debug info 1');
```

The result will be the same in both cases. It's just sugar.

The only important thing here is that when you disable assertions or your
constant, the logging code will be removed by the compiler. This is not just
`if (false)`. This is a full reset.

Benchmarks can be seen here: [benchmarks.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/benchmarks.dart).


## How to make your own logger?

Building a basic custom logger involves defining your log function signature,
the log entry payload, the level logger configuration, and the main logger
manager.

Here is a simplified example of how you can build a logger tailored strictly
to your application's needs:

**1. Define the log function signature**

```dart
import 'package:logger_builder/logger_builder.dart';

typedef LogFn =
    bool Function(Object? message, {Object? error, StackTrace? stackTrace});
```

You can choose `void` as the return value, but if you want to use the logger
together with `assert`, it is better to choose `bool`. If you haven't decided
yet, definitely choose `bool`.

Pay attention to the type of `message` is `Object?`. First, this is done so
that any object can be passed to the logger. The logger will then convert it to
a string itself. Secondly, this makes it possible to use deferred calculations
by passing a function to the logger that will be called only if the log is
output.

**2. Define the Entry Payload**

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

  String get message => _lazyMessage.value;
}
```

This is a structure that will store all information about a specific log, which
will be obtained from the `LogFn` function or calculated independently.

The constructor always requires a reference to `levelLogger` (more on that
below). But in fact, the reference to `levelLogger` is only needed to extract
the data about the level from it: `level`, `levelName`, `levelShortName`. The
reference itself is not saved.

Also, the base class `CustomLog` already has ready-made fields `error` and
`stackTrace`. They are not required to be filled in, but you can use them
if your logging system requires it. `stackTrace` can be used independently of
`error`. But if you do not pass `stackTrace`, and pass `Error` instead of
`Exception` as `error`, then `stackTrace` will be taken automatically from
`error`, if it is there:

```dart
stackTrace ??= error is Error ? error.stackTrace : null;
```

`CustomLog` also has a ready-made `zone` field. By default, it is equal to
`Zone.current`, i.e., the zone in which the logger was called.

**3. Define the Level Logger (handles logic for a specific log level)**

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
      publisher.publish(
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

When extending the `CustomLevelLogger` class, you need to pass several types to
it:

- `Logger` - type of main logger
- `LevelLogger` - type of level logger
- `LogFn` - type of log function
- `Log` - type of log event

The constructor of the `CustomLevelLogger` class accepts several parameters:

- `level` - level of log. It is an integer. The higher the number, the higher
  the level of the log. You can use ready constants from the `Levels` class as
  values. In it there are and those that use `developer.log` and the `logging`
  package: `finest`, `finer`, `fine`, `config`, `info`, `warning`, `severe`,
  `shout`. But there are also additional `trace`, `verbose`, `debug`, `error`,
  `critical`. In any case, it is just numbers: greater than 0 (`Levels.off`)
  and less than 2000 (`Levels.all`). You can use your own values.

- `name` - the name of the log level. This is a string value that you can
  use to output the log. The parameter is mandatory, although it is not
  necessary to use it. In the `CustomLog` structure, this value is stored
  with the name `levelName`.

- `shortName` - short name of the log level. This is an optional parameter. If
  it is not specified, the first character of `name` will be used as
  `shortName`. In the `CustomLog` structure, this value is stored with the
  name `levelShortName`. You can use this value as you wish.

- `noLog` is a no-op function that will be called when this log level is not
  enabled. Since you yourself define the signature of the log function, you
  will have to define this no-op function yourself. That is, its type must
  match exactly the type of the `LogFn`. Pass a global function or static
  method here:

  ```dart
  noLog: _noLog,

  ...

  static bool _noLog(
    Object? message, {
    Object? error,
    StackTrace? stackTrace,
  }) => true;
  ```

  Or an empty closure:

  ```dart
  noLog: (_, {error, stackTrace}) => true,
  ```

  Performance will be the same in both cases.

- `publisher` - a publisher that will be called by default to publish the `Log`
  event. Typically, the publisher handles formatting and outputting the
  results. However, it may also forward the log to other publishers
  (`MultiPublisher`) or place the event processing in an asynchronous queue
  (`AsyncPublisher`). By default, `CustomLogPublisher.noOp` is used, which does
  nothing.

  ```dart
  final log = Logger()
    ..level = Levels.all
    ..publisher = CustomLogPublisher(
      (log) => print(log.message),
    );
  ```

  or:

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

Finally, you need to create the main function `processLog`, which will be
called under the hood instead of `log.info`, `log.error`, etc.

Due to technical features, `processLog` cannot be just a function. It is
a getter of type `LogFn`, which accepts either a function or a `closure` of
the corresponding type. Implement `processLog` as you see fit.

For example, using a closure:

```dart
@override
LogFn get processLog => (message, {error, stackTrace}) {
      publisher.publish(
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

Or using a method:

```dart
@override
LogFn get processLog => _processLog;

bool _processLog(Object? message, {Object? error, StackTrace? stackTrace}) {
  final log = Log(this, message: message, error: error, stackTrace: stackTrace);
  publisher.publish(log);
  return true;
}
```

Theoretically, the second option should be more performant, as it does not
create a `closure` on each call. But in practice, the compiler makes the
difference minimal.

Inside `processLog`, you need to do three things:

1. Create a `Log`.
2. Publish the `Log` via `publisher.publish`.
3. Return `true` (if you decided to follow the advice and use `bool` as
   the return value).

You will have to do all this yourself. Yes, creating a logger requires
writing a large amount of code. But this is only done once, and it will be
YOUR own unique logger.

**4. Define the Main Logger (manages the different level loggers)**

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

  LogFn get debug => _debug.log;
  LogFn get info => _info.log;
  LogFn get error => _error.log;
}
```

When extending the `CustomLogger` class, the same types are used as when
extending `CustomLevelLogger`.

Next, you need to decide which logging levels you need and create the
corresponding level loggers, then register them in the `registerLevels` method
using `registerLevel` method. Then, using the appropriate getters, pass
a reference to the `log` getter of the corresponding logger. Be careful not to
make a mistake here: do not accidentally pass a reference to `processLog`!
`log` will automatically change to `noLog` when logging at this level is
disabled, and to `processLog` when it is enabled!

**5. Use the Logger**

```dart
void main() {
  final log = Logger()
      ..level = Levels.all
      ..publisher = const DefaultLogPublisher();

  log.i('Hello, world!');
  log.e('Something went wrong', error: Exception('Something went wrong'));
}
```

The entire example can be viewed here: [simple_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/simple_logger.dart).


## Lazy Evaluation

When invoking log methods with potentially expensive payload evaluations, you
can use closures. The log entry will lazily convert closures using
`Lazy` and `LazyString` only when the specific level is enabled and printed.

```dart
// The closure will only execute if the 'info' level is currently enabled
log.info(() => jsonEncode(hugeObject));
```

I recommend using closures in all cases when you pass something other than
ready-made values, even if it's a simple string with minor interpolations or
something like `i++`. Better safe than sorry.

The main class for lazy computations is `Lazy`:

```dart
final lazy = Lazy(() => expensiveComputation());
print(lazy.resolved); // expensiveComputation() will be called only here
print(lazy.resolved); // expensiveComputation() will not be called again
```

`Lazy` returns `Object?`. For a typed value, extend the `TypedLazy` class:

```dart
final class LazyString extends TypedLazy<String> {
  final String fallbackValue;

  LazyString(super.unresolved, [this.fallbackValue = 'null']);

  @override
  String convert(Object? resolved) => resolved?.toString() ?? fallbackValue;
}
```

The `convert` function will only be called for values whose type does not match
the specified one. Therefore, if you expect a specific type and conversion from
other types is impossible, throw an exception or return a fallback value.

For `String` use the ready-to-use `LazyString` or `LazyStringOrNull` classes.
If the value type does not match `String`, the `toString()` method will be
called.


## Custom Publishers

At runtime, you can swap out publishers for the whole logger, or just
a specific level:

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
  // Change the publisher globally
  ..publisher = const DefaultLogPublisher()
  // Change the publisher for errors only (e.g. print in red using ansi codes)
  ..[Levels.error].publisher = CustomLogFormatter(
    format: DefaultLogPublisher.format,
    output: (str) => print(red(str)),
  );
```


## Async Publishers

`CustomLogger` does not natively support asynchronous log processing. You can,
of course, specify an asynchronous function as a publisher:

```dart
log.publisher = CustomLogPublisher((log) async {
  await ...
});
```

But the logs will be output in parallel without waiting for each other. In
some cases, this might be exactly what you need. But if the order of log
processing is important to you (for example, when writing to a file), then
this is not the right option for you.

Therefore, for asynchronous processing of logs, `log.publisher` should act
internally to register and coordinate events sequentially.

`logger_builder` already has a set of ready-made asynchronous publishers.


### `AsyncPublisher`

`AsyncPublisher` is a simple version of an asynchronous handler.

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

See an example:
[async_publisher.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher.dart).

### `AsyncPublisherBase`

`AsyncPublisherBase` allows you to create your own handler class.

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

See also an example:
[async_publisher.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher.dart).

> [!NOTE]
> All versions of handlers have a `Base` version.

### `AsyncPublisherWithParam`

`AsyncPublisherWithParam` allows you to add an additional parameter to the
handler.

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

See also an example:
[async_publisher_with_param.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_param.dart).

### `AsyncPublisherWithBuffer`

```dart
Future<void> main() async {
  final asyncPublisher = AsyncPublisherWithBuffer<Log>((logs, retryBuffer) async {
    try {
      await ...;
    } catch (e) {
      retryBuffer.addAll(logs); // Failed logs handled automatically
    }
  });

  final log = Logger()
    ..level = Levels.all
    ..publisher = asyncPublisher;

  log.d('1 Debug message');
  log.i('1 Info message');
  log.e('1 Error message');

  await null; // 3 messages handled

  log.d('2 Debug message');
  log.i('2 Info message');
  log.e('2 Error message');

  log.d('3 Debug message');
  log.i('3 Info message');
  log.e('3 Error message');

  await null; // 6 messages handled

  await asyncPublisher.flush();
}
```

See also an example:
[async_publisher_with_buffer.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer.dart).

And see also `AsyncPublisherWithBufferAndParam`.


## Several Publishers

The `MultiPublisher` helper class allows you to send a log to multiple
publishers.

```dart
final consolePrinter = CustomLogPublisher((log) => print('Console: $log'));
final filePrinter = AsyncPublisher((log) async {/* write to file */});

final multiPublisher = MultiPublisher([
  consolePrinter,
  filePrinter,
]);

log.publisher = multiPublisher;

// ...

await multiPublisher.flush();
```

See also an example:
[multi_publisher.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/multi_publisher.dart).


## Examples

The [example/logger_builder_examples](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/) directory contains more elaborate examples, demonstrating:
- Simple logger
  ([logger](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/simple_logger.dart),
  [usage](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/simple_logger.dart)).
- Multi-parameter log methods
  ([logger](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/complex_logger.dart),
  [usage](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/complex_logger.dart)).
- Complex hierarchy loggers
  ([logger](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/hierarchical_logger.dart),
  [usage](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/hierarchical_logger.dart)).
- Custom formatters converting log directly to JSON dictionaries
  ([logger](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/json_reporter.dart),
  [usage](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/json_reporter.dart)).
- Async publishers:
  - Async publisher
    ([publisher](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher.dart),
    [example](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher.dart))
  - Async publisher with param
    ([publisher](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher_with_param.dart),
    [example](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_param.dart))
  - Async publisher with buffer
    ([publisher](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher_with_buffer.dart),
    [example](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer.dart))
  - Async publisher with buffer and param
    ([publisher](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/async_publisher_with_buffer_and_param.dart),
    [example](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/async_publisher_with_buffer_and_param.dart))
- Multi publisher
    ([publisher](https://github.com/vi-k/logger_builder/blob/main/lib/src/async_publishers/multi_publisher.dart),
    [example](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/multi_publisher.dart))
