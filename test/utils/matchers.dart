import 'package:test/test.dart';

/// Matches the package's own "closed publisher" error rather than any
/// [StateError] at all.
///
/// `throwsStateError` was too loose to tell the guard from the
/// `StreamController`'s own complaint. Deleting `if (isClosed) throw` from
/// `AsyncPipeline.add` left every one of these tests green, because adding
/// to an already-closed controller throws a `StateError` too — a different
/// message, and, more to the point, a different moment: the controller only
/// objects once it is really closed, while the guard also covers the window
/// in which a flush has swapped in a fresh controller that nobody will ever
/// drain.
final throwsPublisherClosed = throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'The publisher is closed',
  ),
);
