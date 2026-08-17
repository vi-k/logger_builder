[![Dart CI](https://github.com/vi-k/logger_builder/actions/workflows/dart.yml/badge.svg)](https://github.com/vi-k/logger_builder/actions/workflows/dart.yml)
[![Pub Publisher](https://img.shields.io/pub/publisher/logger_builder)](https://pub.dev/publishers/yet-another.dev/packages)
![Pub Version](https://img.shields.io/pub/v/logger_builder)
![GitHub License](https://img.shields.io/github/license/vi-k/logger_builder)

A toolkit for creating your own customizable and hierarchical loggers in Dart
with good performance when disabled.

```sh
dart pub add logger_builder
```

## Features

- **Custom Loggers**: Build your own logger classes extending `CustomLogger`
  with tailored log methods, entries, and customizable properties.
- **Hierarchical Loggers**: Inbuilt support for hierarchical structures where
  subloggers inherit capabilities (levels, publishers) from parents,
  with the flexibility to override them.
- **Lazy Evaluation**: Includes utilities like `Lazy` and `LazyString` to avoid
  expensive operations (like string interpolations or JSON encoding) when
  a logging level is disabled.
- **Async & Buffered Publishers**: Base classes like `AsyncPublisherBase` for
  printing logs asynchronously or buffering them before sending (e.g., to an
  analytics service).
- **Transformers**: A `LogTransformer` on the logger or on a single
  destination masks secrets and PII, or drops forbidden logs entirely,
  before they reach any output.
- **Flexible Formatting & Output**: Loggers decouple the **format** step (which
  formats the entry into a string or other object) and the **output** step
  (which decides what to do with the formatted object, like printing to the
  console).


## Table of contents

- [What can this toolkit do?](#what-can-this-toolkit-do)
- [Performance](#performance)
- [Why not just `if (logging)`?](#why-not-just-if-logging)
- [How to make your own logger?](#how-to-make-your-own-logger)
- [Lazy Evaluation](#lazy-evaluation)
- [Custom Publishers](#custom-publishers)
- [Async Publishers](#async-publishers)
- [Several Publishers](#several-publishers)
- [Hierarchical Loggers](#hierarchical-loggers)
- [Transformers](#transformers)
- [Common Scenarios](#common-scenarios)
- [Common Mistakes](#common-mistakes)
- [Using logger_builder in your own package](#using-logger_builder-in-your-own-package)
- [Examples](#examples)

## What can this toolkit do?

Next, there will be examples of logger implementations: what can be done. How
to do them will be explained below.

> [!NOTE]
> The snippets below show the output you get **once logging is switched on**.
> Two things are needed for that, and a fresh logger has neither:
>
> - `..level = Levels.all` (or any other threshold) — a freshly built logger
>   starts at `Levels.off`. That default is deliberate, see
>   [Using logger_builder in your own package](#using-logger_builder-in-your-own-package);
> - `..publisher = ...` — every level starts on a no-op publisher that
>   discards what it gets.
>
> Get one of them wrong and you see silence with no hint which: an
> unconfigured level still reports `isEnabled == true`, because it *is*
> enabled — it just publishes into nothing.

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

You can create nested loggers associated with the main one. Nested loggers do
not need to be disposed of: the parent holds them through weak references, so
once you stop referencing a sublogger it is collected and dropped from the
parent on the next traversal. Therefore, you can safely create them in each
function or unit where needed. See
[Hierarchical Loggers](#hierarchical-loggers) for the inheritance rules.

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

`child` is not a package method — the package gives you the protected
`CustomLogger.sub` constructor and you expose it under whatever name reads
best. This snippet assumes the `Logger` built in
[Hierarchical Loggers](#hierarchical-loggers), which is where `child` is
defined.

See example: [hierarchical_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/hierarchical_logger.dart).

**Any output type**

The output type does not necessarily have to be a `String`. It can be, for
example, ready-made json or a type prepared for conversion to json:

```dart
final log = JsonReporter()
  ..level = Levels.all
  ..publisher = const DefaultJsonPublisher();
log.i('info-event', data: {'id': 2, 'data': 'Info data'});
// {"level":"info","timestamp":1786903488805201,"event":"info-event",
//  "data":{"id":2,"data":"Info data"}}
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


## Why not just `if (logging)`?

If your needs are covered by

```dart
const logging = bool.fromEnvironment('logging');
if (logging) print('User $id logged in');
```

then keep doing that. It costs nothing, and this package does not ask you
to give it up — as shown above, `logging && log.i(...)` is the same trick
and compiles away just as completely.

The difference is *when* the switch is thrown.

`if (logging)` is a **compile-time** switch. One constant turns the whole
program's logging on or off, and the destination — `print` — is written
into every call site. That is fine while the only reader is you, at your
own terminal, right now.

A logger is a **runtime** switch, and that buys four things a bare `print`
cannot:

- **Granularity.** `Levels.off` for the app and `Levels.all` for
  `authLog`: one noisy subsystem, without recompiling and without
  drowning in everything else.
- **Levels.** `print` has exactly one severity. Someone chasing a bug
  wants debug output; the same person in production wants errors only.
- **A destination you can change later.** The call site says *what*
  happened; the publisher decides where that goes. Console today, a file
  or an analytics service tomorrow, both at once when you need it — and
  not one call site changes.
- **Something to hand your users.** A package built on
  `if (logging) print(...)` offers its users nothing: they cannot turn
  its logs on, cannot format them, cannot fold them into their own log
  stream. See
  [Using logger_builder in your own package](#using-logger_builder-in-your-own-package).

And none of it is paid for while logging is off: a disabled level is one
call to an empty function, and under `assert` or a constant the call
disappears entirely.

So it is not one or the other. Use `assert(log.d(...))` for what should be
gone from release builds, and levels and publishers for what should stay
switchable at runtime.


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

  /// A copy is not a new log event: `CustomLog.copy` keeps the level and the
  /// zone, and your copy constructor carries over your own fields — as the
  /// two lines below do. Transformers need this.
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

This is a structure that will store all information about a specific log, which
will be obtained from the `LogFn` function or calculated independently.

The constructor always requires a reference to `levelLogger` (more on that
below). But in fact, the reference to `levelLogger` is only needed to extract
the data about the level from it: `level`, `levelName`, `shortLevelName`. The
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
  `critical`. In any case, it is just numbers: greater than 0 (`Levels.all`)
  and less than 2000 (`Levels.off`). You can use your own values.

- `name` - the name of the log level. This is a string value that you can
  use to output the log. The parameter is mandatory, although it is not
  necessary to use it. In the `CustomLog` structure, this value is stored
  with the name `levelName`.

- `shortName` - short name of the log level. This is an optional parameter. If
  it is not specified, the first character of `name` will be used as
  `shortName`. In the `CustomLog` structure, this value is stored with the
  name `shortLevelName`. You can use this value as you wish.

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
  (`AsyncPublisher`). By default, `CustomLogPublisher.noOp()` is used, which does
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

Or using a method:

```dart
@override
LogFn get processLog => _processLog;

bool _processLog(Object? message, {Object? error, StackTrace? stackTrace}) {
  final log = Log(this, message: message, error: error, stackTrace: stackTrace);
  publishLog(log);
  return true;
}
```

Theoretically, the second option should be more performant, as it does not
create a `closure` on each call. But in practice, the compiler makes the
difference minimal.

Inside `processLog`, you need to do three things:

1. Create a `Log`.
2. Publish the `Log` via `publishLog` — the protected method that applies
   `CustomLogger.transformer` and then hands the log to the publisher.
   Calling `publisher.publish` directly skips the transformer.
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

  LogFn get d => _debug.log;
  LogFn get i => _info.log;
  LogFn get e => _error.log;
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

`CustomLogFormatter` above is the second, shorter route: it is a
`CustomLogPublisher` that splits the job in two — `format` turns a `Log` into
an `Out` object, `output` decides what to do with it. Writing a class like
`DefaultLogPublisher` gives you a name and a place for state; reaching for
`CustomLogFormatter` saves you the class when all you want is to reuse one
`format` with a different `output`, which is exactly what the error level does
here.


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

### The full set

Two independent axes — does the handler need an extra parameter, and does it
work on batches — give four base classes, and each comes in a "do it
yourself" and a "format + output" flavour:

|                      | one log at a time                        | batches                                                |
| -------------------- | ---------------------------------------- | ------------------------------------------------------ |
| **no parameter**     | `AsyncPublisher` / `AsyncFormatter`      | `AsyncPublisherWithBuffer` / `AsyncFormatterWithBuffer` |
| **with a parameter** | `AsyncPublisherWithParam` / `AsyncFormatterWithParam` | `AsyncPublisherWithBufferAndParam` / `AsyncFormatterWithBufferAndParam` |

The `Async*Publisher*` half takes one `handle`/handler callback and you do
everything in it. The `AsyncFormatter*` half splits that in two — `format`
turns the log (or the batch) into an `Out` object, `output` sends that
object somewhere — which is what you want when the same payload goes to
several destinations, or when formatting is the expensive part:

```dart
final asyncFormatter = AsyncFormatter<Log, Map<String, Object?>>(
  format: (log) async => {'level': log.levelName, 'message': log.message},
  output: (out) async => apiClient.post('/logs', data: out),
);
```

Every one of the eight takes the same three optional arguments:

- **`onError`** — called when the handler throws. Without it the error goes
  to the current zone, and in a plain Dart program without an error zone an
  uncaught asynchronous error **terminates the isolate**, after which nothing
  keeps processing your logs. Set it, or wrap the app in `runZonedGuarded`;
- **`sync`** — whether the internal `StreamController` delivers
  synchronously. Leave it alone unless you know you need it;
- **`retryDelay`** — buffered variants only: how long to wait before
  retrying a batch that was handed back through `retryBuffer`. The default
  `Duration.zero` still goes through the event loop, so a dead sink cannot
  starve timers or your own `close()`, but it retries as fast as the loop
  allows. Set a real delay when the destination can be down for a while —
  and note that `close()` then waits for the pending retry.

The `Base` classes (`AsyncPublisherBase` and friends) are for when you want a
named class with its own state instead of a callback; `isClosed` tells you
whether `close()` has been called.

> [!IMPORTANT]
> All of these queues are **unbounded**. If the destination cannot keep up,
> pending logs accumulate until the process runs out of memory. There is no
> overflow policy and no dropped-log counter — bound the input yourself if
> the sink can stall. In the buffered variants, `retryBuffer` is also the
> only thing that keeps a log across a failure: a throwing handler drops
> everything it did not hand back.


## Several Publishers

The `MultiPublisher` helper class allows you to send a log to multiple
publishers.

```dart
// The `<Log>` is required on all three. A publisher stored in a local
// variable has no context type to infer from, so `Log` would become
// `CustomLog` and the assignment to `log.publisher` would not compile.
final consolePrinter = CustomLogPublisher<Log>((log) => print('Console: $log'));
final filePrinter = AsyncPublisher<Log>((log) async {/* write to file */});

final multiPublisher = MultiPublisher<Log>([
  consolePrinter,
  filePrinter,
]);

log.publisher = multiPublisher;

// ...

await multiPublisher.flush();
```

An exception thrown by one publisher does not interrupt publishing: the
remaining publishers still receive the log. Pass `onError` to handle such
errors yourself — it receives the failing publisher along with the error:

```dart
final multiPublisher = MultiPublisher<Log>(
  [consolePrinter, filePrinter],
  onError: (publisher, error, stackTrace) =>
      print('$publisher failed: $error'),
);
```

Without `onError`, the error is reported to the current zone as an uncaught
asynchronous error (in Flutter it ends up in `PlatformDispatcher.onError`,
inside `runZonedGuarded` — in its handler). Note that a plain Dart program
without an error zone terminates the isolate on such errors by default.

`flush()` and `close()` cascade only to the publishers that can be flushed
and closed — the ones implementing `Flushable` and `Closable`. All the
asynchronous publishers do, including the adapter returned by `withParam()`;
a plain `CustomLogPublisher` has nothing to drain and is skipped.

See also an example:
[multi_publisher.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/async_publishers/multi_publisher.dart).


## Hierarchical Loggers

A sublogger is created through the protected `CustomLogger.sub` constructor.
Since it is protected, you expose it the way that suits your logger — usually
a named constructor plus a method that reads well at the call site:

```dart
final class Logger extends CustomLogger<Logger, LevelLogger, LogFn, Log> {
  final String name;

  Logger(this.name);

  Logger._sub(Logger parent, this.name) : super.sub(parent);

  Logger child(String name) => Logger._sub(this, '${this.name}.$name');

  // registerLevels(), getters, ... as before
}
```

```dart
final root = Logger('app')
  ..level = Levels.info
  ..publisher = const DefaultLogPublisher();

final db = root.child('db');       // inherits level and publisher
final http = root.child('http');
```

**What is inherited.** Three things, each with its own link: the `level`, the
per-level publishers, and the `transformer`. A change on the parent reaches
every sublogger whose corresponding link is still up:

```dart
root.level = Levels.debug; // db and http switch to debug too
```

**How a sublogger detaches.** Assigning any of the three directly on the
sublogger drops that link — from then on the sublogger keeps its own value
and ignores the parent:

```dart
http.level = Levels.all;   // http is now independent, db still follows root
root.level = Levels.error; // db → error, http stays at all
```

Assigning the same value is the idiom for unlinking without changing
anything: `child.level = child.level`, `child.transformer =
child.transformer`, and, for publishers, `child[Levels.info].publisher =
child[Levels.info].publisher`.

**How to re-attach.** `relink()` re-inherits all three from the parent and
turns propagation back on. It returns `false` only for a root logger:

```dart
http.relink(); // follows root again
```

A parent keeps its subloggers through weak references, so subloggers never
need disposing — an abandoned branch is collected whole. A sublogger, on the
other hand, holds its parent strongly, so a logger you keep never loses the
chain it inherits from.

A sublogger is not required to register the same levels as its parent. A
per-level publisher for a level the sublogger does not have is skipped
silently; reaching for an unregistered level through `operator []` throws a
`StateError`.

See also an example:
[hierarchical_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/hierarchical_logger.dart).


## Transformers

A transformer runs on every log right before it is handed to the publisher.
Returning a log publishes it instead of the original; returning `null` drops
the log entirely. It exists mainly for security — masking secrets and PII
before they reach any output:

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

Transformers are inherited by subloggers and follow the same link rules as
the level and the publishers (see above).

**Fail-closed.** If the transformer throws, the log is **not** published —
the untransformed log never leaks — and the error goes to the current zone.

**Per destination: `TransformPublisher`.** `CustomLogger.transformer` applies
to everything the logger publishes. To mask for one destination only, wrap
that destination:

```dart
log.publisher = MultiPublisher([
  consolePrinter,                                   // verbatim
  TransformPublisher(fileStorage, transformer: redact), // masked
]);
```

`TransformPublisher` takes its own `onError`; without it, errors go to the
current zone. `flush` and `close` are delegated to the wrapped publisher.

> [!WARNING]
> A transformer must not log through its own logger, and neither must a
> publisher: the nested call comes straight back and would recurse until the
> stack is exhausted. Both cycles are detected — the nested log is dropped
> and a `StateError` is reported. Treat that as a guard against runaway
> recursion, not as a way to log from a transformer.
>
> The guard is synchronous and per logger. It does not catch a cycle that
> goes through a **sublogger** which inherited the same transformer (a
> sublogger is a separate logger with its own guard), and it does not survive
> an **asynchronous hop** — a transformer that defers the nested log with
> `scheduleMicrotask` or a `Future` is outside the guard entirely, and an
> unconditional one will loop forever.


## Common Scenarios

The snippets below use the logger built in
[simple_logger.dart](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/lib/simple_logger.dart):
a `Log` carrying a `message`, and a `Logger` with `d`, `i` and `e`.

### How to log to stdout and stderr

`print` always writes to stdout, so error output ends up mixed into the
program's normal output. Give the error level its own publisher:

```dart
import 'dart:io';

String format(Log log) => '[${log.shortLevelName}] ${log.message}';

final log = Logger()
  ..level = Levels.all
  ..publisher = CustomLogFormatter(format: format, output: stdout.writeln)
  ..[Levels.error].publisher =
      CustomLogFormatter(format: format, output: stderr.writeln);
```

### How to log to a file

Writing to a file is asynchronous, and the writes must not interleave, so
use a buffered async publisher: it gathers logs into batches and processes
one batch at a time.

```dart
import 'dart:io';

final file = File('app.log');

final filePublisher = AsyncPublisherWithBuffer<Log>((logs, retryBuffer) async {
  final batch =
      logs.map((log) => '[${log.shortLevelName}] ${log.message}\n').join();
  try {
    await file.writeAsString(batch, mode: FileMode.append);
  } on Object catch (error) {
    // Keep the batch for the next attempt instead of losing it.
    retryBuffer.addAll(logs);
    stderr.writeln('cannot write to ${file.path}: $error');
  }
});

final log = Logger()
  ..level = Levels.all
  ..publisher = filePublisher;
```

The queue in front of the file is unbounded: if the disk stalls, pending
batches pile up in memory until the process dies. That is the trade-off for
never dropping a log silently — see
[the full set](#the-full-set) for `retryDelay` and the rest.

Drain the queue before the program exits, or the last batch never reaches
the disk:

```dart
await filePublisher.close();
```

`close()` is terminal, and "refuses" is stronger than it sounds: it
processes everything accepted so far, and **any later `log.i(...)` throws a
`StateError` at the call site**. That is deliberate — closing a publisher and
then logging is a shutdown-ordering bug, and finding out immediately beats
feeding logs into a dead buffer — but it does mean a stray log line in a
`finally` can bring the program down. Close last, or use `flush()` when you
only want to wait for the queue to empty and keep logging afterwards.

Note that `flush()` means two different things depending on which publisher
you picked, and both are useful:

- **snapshot** — `AsyncPublisher`, `AsyncFormatter` and their `WithParam`
  variants complete when everything queued *at the moment of the call* has
  been processed. Logs published after it land in the next round;
- **drain** — the buffered variants complete when the buffer is *empty*,
  including logs published after the call. Under a steady stream of logging
  a drain-flush finishes later than a snapshot-flush, and on a busy logger it
  may not finish promptly at all.

A `MultiPublisher` holding one of each mixes the two guarantees, so reach for
`close()` when you need a hard "everything is out" point.

### How to add a timestamp

Record the time in the log, not in the formatter:

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

`DateTime.now()` inside the formatter only tells the truth for synchronous
publishers. As soon as the output is asynchronous or buffered, formatting
happens when the batch is processed rather than when the event occurred —
and every log in a batch ends up with nearly the same, wrong, timestamp.

### How to colour the logs

Colour is part of formatting, so it belongs in the publisher:

```dart
import 'package:ansi_escape_codes/style.dart';

String format(Log log) => '[${log.shortLevelName}] ${log.message}';

final log = Logger()
  ..level = Levels.all
  ..publisher = CustomLogFormatter(format: format, output: print)
  ..[Levels.error].publisher =
      CustomLogFormatter(format: format, output: (str) => print(red(str)));
```

Escape codes are for terminals, not for files: colouring the shared
formatter would put `\x1b[31m` into your log file too. When a log goes to
both, give each destination its own publisher:

```dart
final log = Logger()
  ..level = Levels.all
  ..publisher = MultiPublisher<Log>([
    // Terminal: coloured.
    CustomLogFormatter(format: format, output: (str) => print(red(str))),
    // File: plain text.
    filePublisher,
  ]);
```


## Common Mistakes

**Building the message eagerly**

```dart
log.d('Cache state: ${jsonEncode(cache)}'); // BAD
```

The interpolation runs before `log.d` is even called, so `jsonEncode` runs
whether or not the debug level is enabled — the exact cost this package
exists to avoid. Pass a closure and it is evaluated only if the level is
on:

```dart
log.d(() => 'Cache state: ${jsonEncode(cache)}'); // GOOD
```

See [Lazy Evaluation](#lazy-evaluation).

**Deferring what is never deferred**

The mirror image of the same mistake. A closure pays off only for a level
that can actually be off — on a level you keep enabled at all times it is
evaluated on every call anyway, and all it adds is an allocation:

```dart
log.i(() => 'User $id logged in'); // pointless if `i` is always on
log.i('User $id logged in');       // just pass the value
```

**Exposing `processLog` instead of `log`**

```dart
LogFn get d => _d.processLog; // BAD: always logs
LogFn get d => _d.log;        // GOOD: switches with the level
```

`log` is the field the package swaps between `processLog` and the no-op
function. Handing out `processLog` directly gives you a level that can
never be turned off — and none of the performance the switch exists for.

**Publishing with `publisher.publish` instead of `publishLog`**

```dart
@override
LogFn get processLog => (message, {error, stackTrace}) {
      publisher.publish(Log(this, message: message)); // BAD
      publishLog(Log(this, message: message));        // GOOD
      return true;
    };
```

`publishLog` is what applies `CustomLogger.transformer` before handing the
log on. Going straight to the publisher silently skips it, so masking and
filtering never run.

**Timestamping in the formatter**

`DateTime.now()` in a formatter is the time the log was *printed*, which
stops matching the time it *happened* the moment a buffered or async
publisher is involved. See
[How to add a timestamp](#how-to-add-a-timestamp).

**Exiting without draining an async publisher**

```dart
log.i('done');
exit(0); // BAD: the queued logs are still in memory
```

Async and buffered publishers process logs after the call returns. Await
`flush()` or `close()` before the program ends.

**Logging from inside a transformer**

```dart
log.transformer = (entry) {
  log.d('masking $entry'); // BAD: re-enters the transformer
  return mask(entry);
};
```

The nested call runs the transformer again, and again. Such a call is
detected and dropped with a `StateError`, but the log you meant to write
is lost — collect what you need into a plain list instead, or use
a logger that this transformer never reaches.


## Using logger_builder in your own package

A package that logs through `print` gives its users nothing to work with:
they cannot turn the output on, cannot change its shape, cannot route it
anywhere. Exposing a logger instead costs you one public field and gives
them all three.

**Expose the logger, leave it off**

```dart
// lib/src/log.dart
final packageLog = Logger('my_package');
```

A freshly built logger starts at `Levels.off`, so a user who never touches
it never sees your output — which is what a well-behaved dependency does.
Log freely inside your package; nothing is published until someone asks
for it.

**Let the user decide everything about the output**

```dart
// The user's app:
import 'package:my_package/my_package.dart';

void main() {
  packageLog
    ..level = Levels.info
    ..publisher = myAppPublisher; // their format, their destination
}
```

Do not install a publisher yourself, do not wrap anything in
`runZonedGuarded` on the user's behalf, and do not decide that errors
belong on stderr. Those are application decisions, and taking them makes
your logs a foreign body in someone else's log stream instead of a part
of it.

**Give the hierarchy to the user, too**

Subloggers inherit level and publisher from their parent, so one
assignment configures your whole package — while a user who wants only
your HTTP layer can still say so:

```dart
final httpLog = packageLog.child('http');
final cacheLog = packageLog.child('cache');

// In the app: everything at warning level, the HTTP layer in full.
packageLog.level = Levels.warning;
httpLog.level = Levels.all;
```

**Remember that your `Log` type is public API**

Users write formatters against it, so its fields are part of your
package's contract: adding one is safe, renaming or removing one is
a breaking change. Keep the type exported and documented.


## Examples

The [example/logger_builder_examples](https://github.com/vi-k/logger_builder/blob/main/example/logger_builder_examples/bin/) directory contains more elaborate examples, demonstrating:

### Loggers

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

### Async publishers

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
