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
