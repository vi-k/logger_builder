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
