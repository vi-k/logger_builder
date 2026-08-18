## 0.7.0 (unreleased)

The 0.6.2 work below was never published; the per-level publisher pin
landed on top of it and needed a breaking-change bump, so the unreleased
section became 0.7.0 instead.

**[breaking changes]**

* `logger[level].publisher = ...` no longer detaches the whole logger
  from its parent. It pins that one level; the others keep following the
  parent, and `publisherLinked` stays up.
* The common `logger.publisher = ...` setter no longer overwrites a
  pinned level. This applies to a lone logger as well as a sublogger, so
  the order of a common assignment and its per-level exceptions no
  longer matters.
* `publisherLinked` therefore reports `true` in cases where it used to
  report `false` — the getter itself is unchanged, the rule that clears
  it is.
* The idiom for unlinking without changing a value is per level now
  (`child[level].publisher = child[level].publisher`), and there is no
  idiom left for detaching every publisher at once: assign a common
  publisher, or loop over `levels`.
* `CustomLevelLogger` gains `hasOwnPublisher` and `relink()`. A subclass
  that already declares a member of either name stops compiling.

**New**

* `CustomLevelLogger.hasOwnPublisher` tells a pinned level from one that
  takes its publisher from above — next to `hasPublisher`, which tells a
  real publisher from the no-op one.
* `CustomLevelLogger.relink()` drops the pin and takes from the chain
  again. Unlike `CustomLogger.relink()`, it works on a root logger too:
  the level returns under that logger's common publisher.

## 0.6.2 (unreleased, folded into 0.7.0)

Documentation and the example only: `lib/` is untouched, so there is nothing
to migrate. The example moves to `ansi_escape_codes` 4.x, and the README
snippets that colour a log follow it there.

**Documentation**

* The example depends on `ansi_escape_codes: ^4.0.1`, up from `^3.0.2`. The
  major release renamed and removed a good deal — `Match` to `Piece`, `Link`
  to `OscLink`, `rgb` and `gray` to `rgb256` and `gray256`, every name
  deprecated earlier — but nothing the example used: it analysed clean before
  a line of it was touched. The SDK floor of 4.0.1 is `^3.6.0`, the same as
  this package's, so the floor of the example is where it was.
* The five README snippets that print errors in red call `Styles.red(...)`
  where they called `red(...)`. `ansi_escape_codes` 4.0.0 moved its 530
  top-level style names into constants of a single class, `Styles`, so the
  old form no longer compiles against the version the example now uses. The
  import is unchanged: `Styles` comes from
  `package:ansi_escape_codes/style.dart` like the names it replaces.
* `console.dart` in the example measures the width of a line with
  `lengthWithoutEscapeCodes`, which 4.x has and 3.0.2 did not, instead of
  building a cleaned copy of the string and asking for its length. Same
  answer, one copy of the string fewer.

## 0.6.1

Documentation only: `lib/` is untouched, so there is nothing to migrate.
Three README claims that had never been measured now are, and the benchmark
sections behind them ship with the example.

**Documentation**

* The paragraph on `processLog` as a closure versus as a method no longer
  says the method avoids "creating a closure on each call" — nothing does.
  `processLog` is read once per level toggle, so the closure is allocated
  when a level is switched on, not when a log is written. Measured over 1M
  calls per form, the two land within 2 ns of each other, and which one is
  ahead depends on the compiler: AOT gave 10.4 ns for the closure against
  11.9 ns for the method, the JIT gave 11.9 against 11.7.
* "Use closures in all cases" now carries the asymmetry that justifies it:
  with the level enabled a closure adds about 3 ns to a call that costs
  ~135 ns anyway, and with the level disabled it turns 41 ns into 4 ns. The
  two lazy forms are also told apart — a tear-off of an existing function
  allocates nothing per call and comes to 1.9 ns on a disabled level, while
  a closure literal allocates one every call, on or off.
* "`print` always writes to stdout" is scoped to native targets. On the web
  `print` goes to `dartPrint` if the embedder defines one and to
  `console.log` otherwise — the same code in `dart compile js` and in
  `dart compile wasm` — and `dart:io` there compiles only to throw
  `UnsupportedError` at runtime, so the stdout/stderr recipe builds and then
  fails at the user's. A note under that section says all of this, including
  that Dart never calls `console.error`, so the two streams cannot be split
  on the web at all.
* `benchmarks.dart` gains the three sections those numbers come from: the
  same cheap payload through eager interpolation, a tear-off and a closure
  literal, at an enabled and at a disabled level, plus two loggers differing
  in exactly one line — whether `processLog` is a closure or a method.
* The hierarchical example renames `withAddedName` to `child`. The README
  stopped teaching `withAddedName` in 0.6.0, because no published API has
  that name, but the example it links to for that very section still defined
  it.

## 0.6.0

The 0.5.1 work below was never published; an independent review of the
whole code base then found defects that need behaviour changes, so the
unreleased section became a minor bump instead.

**[breaking changes]**

* `environment.sdk` is now `^3.6.0`, up from `^3.2.0`, matching the
  `oldest-supported` CI job and the example package — the declared floor is
  the one actually exercised. `^3.2.0` was true for pure Dart, verified by
  running the package on a real 3.2.0 SDK, but nothing in CI proved it.
* `meta` is now `^1.15.0`, down from `^1.16.0`. This is what made the package
  usable from Flutter at all: Flutter pins `meta` from its own SDK, with an
  *exact* version in older releases (3.24 and 3.27 both pin 1.15.0), so
  `^1.16.0` failed version solving there — on a Flutter whose Dart satisfied
  the declared floor. Nothing in the package needs a newer meta: only
  `@protected`, `@visibleForTesting` and `@immutable` are used. With both
  changes the first usable Flutter is 3.27 instead of 3.29.
* `CustomLevelLogger` now rejects a `level` outside `(Levels.all,
  Levels.off)` with an `ArgumentError`, in every build mode. Those two are
  thresholds, not levels: a level logger registered at `Levels.off` stayed
  enabled with `logger.level = Levels.off`, silently defeating "logging is
  completely disabled".
* Registering one `CustomLevelLogger` instance in two loggers now throws a
  `StateError`. It used to succeed and hand the first logger's logs to the
  second one's publisher and transformer.
* `TransformPublisher.close()` is terminal and idempotent, like every other
  publisher: `publish` afterwards throws a `StateError` and repeated calls
  return the same future. Previously logs still went through, unless the
  wrapped publisher happened to implement `Closable`.
* A sublogger now holds its parent with a strong reference (the parent
  still holds subloggers weakly). An intermediate logger the caller did not
  keep used to be collected, after which `level`, `publisher` and
  `transformer` changes stopped reaching its descendants while they still
  reported themselves linked and `relink()` returned `false` forever.

**New**

* `AsyncPublisherWithBufferBase.onDropped` and the same on
  `AsyncPublisherWithBufferAndParamBase` — called with the entries dropped
  because they were handed back to the retry buffer after `close()`. That
  loss is by design (they can never be processed), but it used to be
  invisible: no error, no callback, no counter. A randomized stress run
  dropped 163 entries without a trace.
* `CustomLevelLogger.hasPublisher` — whether a level has a publisher that
  goes somewhere, or is still on the no-op one every level starts on. The
  second state is indistinguishable from a working level otherwise: the log
  function returns normally and `isEnabled` is `true`, because the level *is*
  enabled. The no-op publisher is private, so nothing outside the package
  could tell.
* `CustomLogger.onError` — one hook for every error the logger catches on the
  publish path: a throwing `transformer`, a reentrancy guard violation, and a
  throwing publisher. With no handler set each case keeps its previous
  behaviour, so nothing changes for existing code: the first two go to the
  current zone, and a publisher error keeps propagating out of the logging
  call. Setting it is what makes logging unable to break the application that
  logs — in a plain Dart program without an error zone, the zone route
  terminates the isolate, so a bug in a masking transformer used to take the
  process down with no way to opt out. Unlike `level`, the publishers and
  `transformer`, it is resolved through the parent chain instead of being
  copied down: a sublogger with no handler of its own uses its parent's,
  there is no link flag, and `relink()` does not affect it.

**Fixes**

* `CustomLogger.isLoggable` no longer contradicts itself at the thresholds:
  `isLoggable(Levels.off)` was `true` for a logger set to `Levels.off`.
  `Levels.all` and `Levels.off` are thresholds, not levels, and no level
  logger can be registered on either, so both now answer `false`.
* `CustomLogger.levels` returns a snapshot instead of a live view of the map
  keys, so registering a level while iterating it no longer throws
  `ConcurrentModificationError`.
* `TransformPublisher.flush()` after `close()` completes without touching the
  wrapped publisher, like every sibling. With an inner publisher that is
  `Flushable` but not `Closable` it kept flushing through one it had already
  disowned.
* Reading `isClosed` (or calling `flush`) on a buffered publisher no longer
  creates its queue. Asking whether a publisher was closed used to
  materialise a `StreamController` with a live subscription nobody would ever
  close, and pinned the zone that receives handler errors to whoever asked
  first.
* `flush()` on the unbuffered publishers no longer moves error routing:
  re-creating the internal listener happens in the zone the publisher was
  constructed in, not the zone that flushed.
* A throwing `Lazy` factory is memoized like `late final` — the error is
  stored, the closure released, and later accesses rethrow it. It used to run
  again on each access, so a factory with a side effect ran once per
  publisher in a `MultiPublisher`, while the class promised the source had
  been replaced by the result.
* Toggling a level that is already in the requested state is a no-op.
  `processLog` allocates a fresh closure in every documented pattern, so
  re-toggling was pure waste (3M closures for 50 level assignments over 20k
  linked subloggers) and it changed the identity of a function a caller may
  have hoisted.
* `close()` on a buffered publisher no longer sleeps through a pending
  `retryDelay`. The retry `Timer` was not kept anywhere, so shutdown latency
  scaled with `retryDelay` — and the entries it waited for were dropped
  afterwards anyway. The timer is now cancelled and one prompt final attempt
  is made instead.
* `flush()` on a buffered publisher no longer reports an empty queue while a
  `close()` is still draining. `isClosed` flips when `close()` is *called*,
  so `flush()` short-circuited to an already-completed future: a false
  all-clear at exactly the moment durability matters. It now returns the
  close.
* A level registered on a sublogger that still follows its parent takes the
  parent's publisher for *that* level, instead of the parent's common
  publisher. Parent and child used to publish the same level to different
  destinations while `publisherLinked` reported `true`.
* A buffered publisher whose handler keeps returning its batch through the
  retry buffer no longer starves the event loop. Retries were re-ticked
  through the microtask queue, which never yields: with the sink down,
  timers, I/O and the application's own `close()` never got a turn and the
  isolate wedged. Retries now go through the event loop, and the new
  `retryDelay` (default `Duration.zero`) spaces them out.
* A *synchronous* publisher that logs through the level it publishes for is
  now caught the same way a reentrant transformer is: the nested log is
  dropped and a `StateError` is reported. It used to recurse about 2570
  frames into a `StackOverflowError`, running the transformer and the
  publisher's side effects once per frame. The guard is per level logger, so
  a publisher that logs at a *different* level of the same logger is allowed
  — a cycle still trips it on the way back. An asynchronous publisher is
  outside the guard entirely: its `handle` runs after `publish` returned, so
  a handler that logs into its own logger grows the queue without bound
  instead of overflowing the stack. That limit is now documented rather than
  glossed over.
* A throwing `format` in `AsyncFormatterWithBuffer` and
  `AsyncFormatterWithBufferAndParam` returns the whole batch to the retry
  buffer instead of dropping it. There was no other point at which the
  caller could hand it back, so the batch vanished silently.
* Retrying one copy of a log that appears twice in a batch no longer
  withdraws the other copy from `output`.
* A level registered after `publisher` was assigned inherits it, and
  `relink()` applies the parent's common publisher to levels the parent
  does not have. Such a level reported itself enabled while publishing into
  the no-op publisher.
* `CustomLogger.sub` and `relink()` no longer dispatch through the
  overridable `level`/`publisher`/`transformer` setters, so a subclass that
  overrides one no longer crashes while the superclass is still
  constructing.
* Creating subloggers is no longer quadratic: registration pruned the whole
  list every time. Creating 16k subloggers under one parent went from 916ms
  to 6ms.
* `MultiPublisher.flush()` after `close()` completes immediately instead of
  cascading into the wrapped publishers.
* The publisher returned by `withParam()` now implements `Flushable` and
  `Closable`, delegating both to the publisher that owns the shared queue.
  It implemented neither, and `MultiPublisher` and `TransformPublisher`
  select members with a type test — so the adapter was skipped: `flush()`
  and `close()` completed successfully, `isClosed` on the real publisher
  stayed `false`, and every queued log was lost at shutdown with no error,
  no callback and no diagnostic. Because the queue is shared, closing any
  adapter closes it for all of them.
* `AsyncFormatterWithBufferAndParam` matches the log half of an entry by
  identity when computing what is left for `output`, like
  `AsyncFormatterWithBuffer` already did. It used a structurally keyed map,
  so a `CustomLog` subclass with value equality made two distinct logs
  interchangeable: the entry handed back to the retry buffer was passed to
  `output` *and* re-queued, while the other one was silently withdrawn and
  never published.

**Documentation**

* `CustomLevelLogger.log` warns against hoisting it into a variable:
  enabling and disabling a level swaps the field, so a stored function is a
  snapshot that keeps publishing after `logger.level = Levels.off`.
* `CustomLevelLogger.publisher` says that reading it and publishing yourself
  bypasses `CustomLogger.transformer` — the transformer is a convenience on
  the library's own path, not an enforced boundary.
* The `Lazy` warning covers `async` functions, which the type test also calls:
  `Instance of 'Future<...>'` gets logged and the future's error becomes an
  unhandled zone error. One mistake, two failures.
* `pruneSubloggers()` and the three `*Linked` getters are no longer marked
  `@visibleForTesting`. The first is the library's own memory-management
  primitive, called on every propagation; the others answer "is this
  sublogger still following its parent?", which is a fair question in
  production given `relink()` is public.
* `analysis_options.yaml`: `require_trailing_commas` carries a note that it
  only works while the language version stays below 3.7 — the 3.7 formatter's
  tall style removes the very commas it demands, measured at 43 issues
  against a freshly formatted tree. Also dropped two deprecated rules (one of which was
  suppressed at every single trigger site), commented out three
  Flutter-only rules and three non-existent excludes, moved eight rules
  `lints/recommended` has since absorbed into the inherited block, marked the
  rules that are still experimental,. `unnecessary_ignore` is left off on
  purpose: it does not exist in the 3.6.0 analyzer the `oldest-supported` job
  pins, and suppressing the `undefined_lint` warning that would cause costs
  more than the rule is worth.
* The `*Linked` flags double as in-progress markers — they are cleared before
  propagation recurses and restored after — and that is the only thing
  stopping a cycle in the sublogger graph from recursing until the stack is
  exhausted. `registerSublogger` is protected, so a subclass can build one.
  Nothing said so and no test covered it; both now do.
* CI now validates the published archive, runs every example, and smoke-tests
  the web and wasm targets pub.dev advertises. Dependabot watches the `pub`
  dependencies as well as the actions, `actions/checkout` is SHA-pinned like
  `setup-dart` already was, and a weekly scheduled run compensates for the
  absence of a committed lockfile.
* The example package declared `sdk: ^3.2.0`, mirroring the library, and
  could not resolve there: `logging` needs ^3.4.0, `ansi_escape_codes` and
  `lints` need ^3.6.0. It also declared a `test` dev dependency with no
  `test/` directory.
* New README sections: "Hierarchical Loggers" (including `CustomLogger.sub`,
  which was never documented) and "Transformers" (the 0.5.0 headline feature,
  previously mentioned only under "Common Mistakes").
* The "How to make your own logger?" tutorial did not compile: step 4
  defined `debug`/`info`/`error` getters while step 5 called `i`/`e`. The
  prose also swapped `Levels.all` with `Levels.off` and named the `CustomLog`
  field `levelShortName` instead of `shortLevelName`.
* The reentrancy guard is documented at its real reach: it is synchronous —
  per logger for the transformer, per level logger for the publisher — so it
  does not catch a cycle through a sublogger that inherited the same
  transformer, nor one that crosses an asynchronous hop.
* The unbounded queues, the dropped retry buffer on `close`, the lazily
  created buffered queue and its zone, and `Lazy` calling any zero-argument
  value are all documented now.
* The "Several Publishers" example did not compile, in the README and in the
  `MultiPublisher` dartdoc alike: with the publishers bound to locals first
  there is no context type, so `Log` was inferred as `CustomLog` and the
  assignment to `logger.publisher` was rejected. All three constructors now
  carry the type argument, with a note on why it is needed.
* A throwing `handle`/`output` in the buffered publishers is documented at
  its real reach: only what it placed in the retry buffer survives, the rest
  is dropped, and reporting the error does not preserve it. `format` is the
  one exception (it retries the whole batch) because `output` never ran.
* The two parameterized publisher bases carry the same warnings as their
  twins: the unbounded queue on `AsyncPublisherWithParamBase`, and the
  unbounded buffer, the dropped-at-close entries and the lazily created queue
  on `AsyncPublisherWithBufferAndParamBase`. Both omissions were the same
  contracts, just undocumented on half the family.
* The class documentation of `CustomLogger` and `CustomLevelLogger` no longer
  describes "message builders and printers" — an API removed in 0.3.0 and
  replaced by `CustomLogPublisher`. It was the first prose on the pub.dev API
  page for the two most important classes in the package.
* `AsyncPublisherWithBufferBase` no longer contradicts its own `close()`:
  the class note said logs in the retry buffer *when* `close` is called are
  dropped; only logs handed back *after* it are.
* The README no longer teaches `withAddedName`, which does not exist in the
  package and was never defined in the README either — the "Using
  logger_builder in your own package" section was uncompilable end to end.
  It now uses the `child(...)` the README itself builds, and says that the
  name is yours to choose over the protected `CustomLogger.sub`.
* The README's opening note said a logger needs only `..level = ...` before
  it says a word. It also needs `..publisher = ...`: every level starts on a
  no-op publisher, and an unconfigured level still reports `isEnabled` as
  `true`, so the two mistakes look identical.
* The README said `close()` "refuses new logs". It throws a `StateError` at
  the logging call site, which is now stated, along with the two different
  meanings of `flush()` — snapshot for the unbuffered publishers, drain for
  the buffered ones.
* New README section "The full set": the 2x2 table of the eight asynchronous
  classes, what separates the `AsyncFormatter*` half from the rest, and the
  three shared arguments. `AsyncFormatter`, `retryDelay`, `Flushable`,
  `Closable`, `sync` and `isClosed` appeared in the README zero times before
  this.

## 0.5.1 (unreleased, folded into 0.6.0)

* A log transformer that logs through its own logger — or into its own
  `TransformPublisher` — no longer recurses: the reentrant call is
  detected, the nested log is dropped and a `StateError` is reported to
  `onError` or the current zone. Previously such a call recursed until
  the stack was exhausted; on the way out every frame published its own
  log (measured: ~2700 duplicates from one logging call), and the
  `StackOverflowError` could escape `Zone.handleUncaughtError` unhandled
  and terminate the isolate. Any cycle that comes back to a logger whose
  transformer is already running is covered; logging into an unrelated
  logger is unaffected, and chained transform publishers do not trip the
  guard. There is no cost when `transformer` is `null` (the default).
(The README sections "Why not just `if (logging)`?", "Common Scenarios",
"Common Mistakes" and "Using logger_builder in your own package" were
originally listed here. They landed after the `Release 0.5.1` commit, so they
belong to 0.6.0 and are credited there.)
* The README and the bundled examples now publish via
  `CustomLevelLogger.publishLog` instead of `publisher.publish`. They had
  been left on the pre-0.5.0 form, so loggers copied from them ignored
  `CustomLogger.transformer` — exactly the pitfall the 0.5.0 note
  described.

## 0.5.0

* Pre-publication log processing: the new `LogTransformer` typedef
  (`Log? Function(Log)`), the `CustomLogger.transformer` property applied
  to every log right before publishing (inherited by subloggers like
  `level`/`publisher`, same link/unlink/`relink` semantics), and the
  `TransformPublisher` wrapper for per-destination transformation.
  Returning `null` drops the log. Fail-closed: a throwing transformer
  drops the log and reports the error to `onError`
  (`TransformPublisher`) or the current zone.
* [breaking changes] `CustomLevelLogger` gains the protected `publishLog`:
  `processLog` implementations must call it instead of
  `publisher.publish(...)`, otherwise `CustomLogger.transformer` is
  ignored.
* The new protected `CustomLog.copy` copies level fields and the zone from
  an existing log and assigns `error`/`stackTrace` verbatim — the building
  block for `copyWith` in subclasses (a copy keeps the log's identity: no
  new number or time should be minted).

## 0.4.0

* [breaking changes] Publisher lifecycle interfaces: `HasFlush` is renamed
  to `Flushable` (`HasFlush` remains as a deprecated alias), and the new
  `Closable` interface exposes `close()`. All async publishers implement
  both; `MultiPublisher.close()` closes every `Closable` publisher in its
  list.
* [breaking changes] `MultiPublisher.flush` with `onError` set now routes
  each publisher's error to the callback and completes normally; without
  `onError` the previous behavior (`ParallelWaitError`) is preserved.
  `close` errors are routed the same way.
* [breaking changes] `MultiPublisher` copies the publisher list at
  construction; mutating the original list no longer affects the publisher.
* [breaking changes] `CustomLevelLogger` is now an `abstract base class`:
  it can be extended, but no longer implemented outside the package.
* New hierarchy management API: `CustomLogger.levels` lists the registered
  level values (a live view); `CustomLogger.relink()` re-attaches an
  unlinked sublogger to its parent (re-inheriting the level and publishers).
  The unlink idiom (`child.level = child.level`) is now documented.
  Note: a subclass that already declares a compatible member named `levels`
  or `relink` will silently override the new API — rename such members.
* `MultiPublisher` now has a closed state: `publish` after `close()` throws
  a `StateError`, repeated `close()` calls return the same future, and
  a new `isClosed` getter reports the state. A throwing `onError` callback
  no longer escapes to the logging call site or replaces the original
  error in `flush`/`close` — the secondary error is reported to the
  current zone.
* The `public_member_api_docs` lint is enabled; every public member is
  documented.

## 0.3.3

* `AsyncPublisherWithBuffer`/`AsyncPublisherWithBufferAndParam`: `flush()` no
  longer hangs on an idle queue — it completes immediately. Flush has drain
  semantics: it also waits for logs published after the call, until the
  buffer becomes empty.
* All async publishers: a new optional `onError` callback receives errors
  thrown by the handler; without it, the error is reported to the current
  zone (same as `MultiPublisher`). A throwing handler no longer stalls the
  queue, loses the retry buffer, or leaves `flush()` hanging.
* All async publishers: a new `isClosed` getter. `publish` after `close()`
  now always throws a `StateError` (buffered publishers used to silently
  accept logs into a dead buffer); `flush()` after `close()` completes
  immediately instead of resurrecting the publisher; repeated `close()`
  calls are no-ops returning the same future.
* `AsyncPublisher`/`AsyncPublisherWithParam`: concurrent `flush()` calls are
  now serialized — an overlapping flush no longer hangs forever and no
  longer loses queued logs.
* Buffered publishers: `close()` now drains the queue completely — logs
  published while a batch was in flight are processed instead of being
  silently dropped. Entries returned to the retry buffer after closing are
  dropped by design (documented).
* All async publishers: an `onError` callback that itself throws can no
  longer stall the queue; the secondary error is reported to the current
  zone and processing continues.
* `AsyncFormatter` family: when `Out` is `Object?`/`dynamic`, an
  asynchronous `format` result is now awaited instead of being passed to
  `output` as an unresolved `Future`.
* `AsyncFormatterWithBuffer`/`AsyncFormatterWithBufferAndParam`: the batch
  passed to `output` now reflects retry-buffer additions made during an
  asynchronous `format`.
* `TypedLazy` (`LazyString`, `LazyStringOrNull`): reading `resolved` after
  `value` now returns the converted value instead of leaking an internal
  sentinel object.
* `LazyString.resolved`: the default `fallbackValue` is now `'null'`, same
  as the main constructor.
* `CustomLevelLogger`: an empty `name` now throws an `ArgumentError` in all
  build modes (previously an assert, and a `RangeError` in release); the
  default `shortName` is the first code point of the name, correct for
  non-BMP characters.
* Hierarchy: setting a per-level publisher on a logger no longer throws
  mid-propagation when a sublogger did not register that level.
* Hierarchy: sublogger bookkeeping no longer uses a `Finalizer` that kept
  the parent logger strongly reachable through its live subloggers; dead
  weak references are pruned automatically during traversals.
* Internal stream subscriptions are now stored and cancelled on `close()`.
* Docs: dartdoc for `HasFlush`, async publisher members, the `Lazy` family,
  `Levels` constants and `CustomLog.zone`.
* Tests: the async publisher family, the `Lazy` family, and level/hierarchy
  edge cases are now covered (63 new tests).

## 0.3.2

* `MultiPublisher`: an exception thrown by one publisher no longer interrupts
  publishing to the remaining publishers and no longer propagates to the
  logging call site. The new `onError` callback receives the failing publisher
  along with the error; without it, the error is reported to the current zone
  as an uncaught asynchronous error.
* `MultiPublisher.flush`: a synchronous throw from one publisher's `flush` no
  longer prevents flushing the others.

## 0.3.0-0.3.1

* [breaking changes] Refactor a builder and a printer to one publisher.
* Add the async publisher family: `AsyncPublisher`, `AsyncPublisherWithParam`,
  `AsyncPublisherWithBuffer`, `AsyncPublisherWithBufferAndParam` and
  `MultiPublisher` (recorded retroactively).
* Upgrade ansi_escape_codes to 3.0.2 for examples.

## 0.2.0

* [breaking changes] Rename `LazyString` to `LazyStringOrNull` and
  `LazyNonNullableString` to `LazyString`.
* Refactor `hierarchical_logger.dart` example to use `LazyString` for path.

## 0.1.3-0.1.4

* Fix bug with builder and printer inheritance in subloggers.

## 0.1.2

* Add a CI badge to README.
* Remove vm_service from example.
* Add GitHub Actions for CI.
* Downgrade Dart SDK constraint to 3.2.0.
* Downgrade meta to 1.16.0.

## 0.1.0-0.1.1

* Initial version.
