## 0.6.0

The 0.5.1 work below was never published; an independent review of the
whole code base then found defects that need behaviour changes, so the
unreleased section became a minor bump instead.

**[breaking changes]**

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

**Fixes**

* A buffered publisher whose handler keeps returning its batch through the
  retry buffer no longer starves the event loop. Retries were re-ticked
  through the microtask queue, which never yields: with the sink down,
  timers, I/O and the application's own `close()` never got a turn and the
  isolate wedged. Retries now go through the event loop, and the new
  `retryDelay` (default `Duration.zero`) spaces them out.
* A publisher that logs through the logger it publishes for is now caught
  the same way a reentrant transformer is: the nested log is dropped and a
  `StateError` is reported. It used to recurse about 2570 frames into a
  `StackOverflowError`, running the transformer and the publisher's side
  effects once per frame.
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

* New README sections: "Hierarchical Loggers" (including `CustomLogger.sub`,
  which was never documented) and "Transformers" (the 0.5.0 headline feature,
  previously mentioned only under "Common Mistakes").
* The "How to make your own logger?" tutorial did not compile: step 4
  defined `debug`/`info`/`error` getters while step 5 called `i`/`e`. The
  prose also swapped `Levels.all` with `Levels.off` and named the `CustomLog`
  field `levelShortName` instead of `shortLevelName`.
* The reentrancy guard is documented at its real reach: it is synchronous
  and per logger, so it does not catch a cycle through a sublogger that
  inherited the same transformer, nor one that crosses an asynchronous hop.
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
* `AsyncPublisherWithBufferBase` no longer contradicts its own `close()`:
  the class note said logs in the retry buffer *when* `close` is called are
  dropped; only logs handed back *after* it are.

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
* New README sections: "Why not just `if (logging)`?", "Common Scenarios"
  (stdout/stderr, files, timestamps, colour), "Common Mistakes" and
  "Using logger_builder in your own package".
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
