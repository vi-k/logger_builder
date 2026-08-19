// Not part of the public API: not exported by the package barrel.
// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:collection';

/// The shared body of the two buffered formatters.
///
/// `AsyncFormatterWithBuffer` and `AsyncFormatterWithBufferAndParam` differ
/// in exactly two things: the element type, and how a counted map keys it.
/// Everything else — retry the whole batch when `format` throws, work out
/// what survived, skip `output` when nothing did — was the same fifty-five
/// lines twice, and the cost of that was not hypothetical: the review's L8
/// had to be fixed here and tested here twice over.
///
/// The public `format` and `output` fields stay on their own classes, where
/// their dartdoc is what pub.dev shows. Only the body moves.
///
/// Not exported by the package.
FutureOr<void> handleBatch<E, Out>({
  required List<E> entries,
  required List<E> retryBuffer,
  required FutureOr<Out> Function(List<E> entries, List<E> retryBuffer) format,
  required FutureOr<void> Function(
    Out out,
    List<E> entries,
    List<E> retryBuffer,
  ) output,
  required HashMap<E, int> Function() counter,
}) {
  final FutureOr<Out> formatted;
  try {
    formatted = format(entries, retryBuffer);
  } on Object {
    // A throwing format leaves the caller no point at which it could hand
    // the batch back, so retry it wholesale rather than dropping it.
    retryWholeBatch(entries, retryBuffer);
    rethrow;
  }

  if (formatted is Future<Out>) {
    return formatted.then(
      (out) => _output(out, entries, retryBuffer, output, counter),
      onError: (Object error, StackTrace stackTrace) {
        retryWholeBatch(entries, retryBuffer);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  return _output(formatted, entries, retryBuffer, output, counter);
}

/// The retry buffer can only ever hold entries from this batch, so restoring
/// the whole batch means replacing whatever `format` managed to add.
void retryWholeBatch<E>(List<E> entries, List<E> retryBuffer) {
  retryBuffer
    ..clear()
    ..addAll(entries);
}

/// Hands [out] to [output], unless `format` kept the whole batch.
///
/// It used to be called regardless, with an empty list of entries and
/// whatever payload `format` had built — an empty request on every retry, to
/// a sink that had already been told nothing got through.
FutureOr<void> _output<E, Out>(
  Out out,
  List<E> entries,
  List<E> retryBuffer,
  FutureOr<void> Function(Out, List<E>, List<E>) output,
  HashMap<E, int> Function() counter,
) {
  final remaining = remainingEntries(entries, retryBuffer, counter);

  return remaining.isEmpty ? null : output(out, remaining, retryBuffer);
}

/// The entries of [entries] that were not handed back through [retryBuffer].
///
/// Counted, not a set: a batch may legitimately hold the same entry twice,
/// and handing one copy back must not withdraw the other from `output`. The
/// keying is the caller's, because the two formatters need different
/// answers — identity for a bare log, and "same param, same log by
/// identity" for a pair.
List<E> remainingEntries<E>(
  List<E> entries,
  List<E> retryBuffer,
  HashMap<E, int> Function() counter,
) {
  if (retryBuffer.isEmpty) {
    return entries;
  }

  final retried = counter();
  for (final entry in retryBuffer) {
    retried[entry] = (retried[entry] ?? 0) + 1;
  }

  final remaining = <E>[];
  for (final entry in entries) {
    final count = retried[entry] ?? 0;
    if (count > 0) {
      retried[entry] = count - 1;
    } else {
      remaining.add(entry);
    }
  }

  return remaining;
}
