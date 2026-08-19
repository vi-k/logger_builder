// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import 'dart:async';

/// Hands [error] to [onError], or to the current zone when there is none.
///
/// These twelve lines lived in five places — both unbuffered bases,
/// `BufferedPipeline`, `TransformPublisher`, and once more for the dropped
/// entries — differing only in the wording of the comment above them. The
/// duplication was not idle: it is the shape in which a fix reaches one copy
/// and not the others.
///
/// A throwing handler must not break its caller, so the handler's own error
/// goes to the zone.
///
/// Not exported by the package.
void reportTo(
  void Function(Object error, StackTrace stackTrace)? onError,
  Object error,
  StackTrace stackTrace,
) {
  if (onError == null) {
    Zone.current.handleUncaughtError(error, stackTrace);

    return;
  }

  guarded(() => onError(error, stackTrace));
}

/// Runs [body] and sends anything it throws to the current zone.
///
/// The callbacks this package hands out — `onError`, `onDropped` — belong to
/// the user, and a throwing one must not take the queue, the delivery or the
/// shutdown with it. Separate from [reportTo] because `onDropped` carries
/// entries rather than an error and cannot use it.
void guarded(void Function() body) {
  try {
    body();
  } on Object catch (error, stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
