part of 'async_publisher_with_buffer.dart';

/// A base class for asynchronous publishers that buffer logs alongside
/// contextual parameters, emitting batches of parameter-log pairs.
///
/// This bridges the batched workflow of buffer-based publishers with the
/// contextual routing of parameter-based publishers.
///
/// > [!IMPORTANT]
/// > The buffer is unbounded. If the handler cannot keep up — or keeps
/// > handing batches back through the retry buffer while the sink is down —
/// > the queue grows until the process runs out of memory. There is no
/// > overflow policy; bound the input yourself if the sink can stall for
/// > long. Entries handed back to the retry buffer *after* [close] was called
/// > cannot be processed and are dropped — set [onDropped] to see them.
/// > Entries already queued when [close] was called are drained (see
/// > [close]).
/// >
/// > The queue is created lazily, on the first publish or [close], not in
/// > the constructor ([flush] and [isClosed] no longer create it). Without an
/// > [onError] the zone that receives handler errors is therefore the one
/// > that published first, not the one that built the publisher.
///
/// Example usage:
///
/// ```dart
/// final class MetricsPublisher extends AsyncPublisherWithBufferAndParamBase<String, Log> {
///   @override
///   Future<void> handle(
///     List<(String, Log)> entries,
///     List<(String, Log)> retryBuffer,
///   ) async {
///     try {
///       await metricsClient.sendBatch(entries); // entries are a list of (String source, Log log)
///     } catch (e) {
///       retryBuffer.addAll(entries); // Queue failed logs back for next flush
///     }
///   }
/// }
///
/// final publisher = MetricsPublisher();
/// log.publisher = publisher.withParam(source);
/// ```
abstract base class AsyncPublisherWithBufferAndParamBase<Param extends Object?,
        Log extends CustomLog> extends _BufferedFacade<(Param, Log)>
    implements Flushable, Closable {
  /// Creates the publisher and its buffered processing queue.
  AsyncPublisherWithBufferAndParamBase({
    super.sync,
    super.onError,
    super.onDropped,
    super.retryDelay,
    super.maxRetries,
    super.maxQueueSize,
  });

  /// Processes a batch of buffered parameter-log [entries].
  ///
  /// Entries added to [retryBuffer] are placed back at the front of the
  /// queue and retried with the next batch.
  ///
  /// > [!IMPORTANT]
  /// > [retryBuffer] is the only way to keep an entry. A throwing [handle] —
  /// > synchronously or through its future — does not retry the batch: the
  /// > error is routed to [onError] or the current zone, and every entry not
  /// > already handed back is dropped. Wrap the failing work in a
  /// > `try`/`catch` and `retryBuffer.addAll(entries)` there.
  @override
  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  );

  /// Returns a [CustomLogPublisher] that publishes into this shared buffer
  /// with the given [param] attached to every log event.
  ///
  /// The returned publisher also implements [Flushable] and [Closable],
  /// delegating both to this publisher, so it behaves correctly inside
  /// a `MultiPublisher` or a `TransformPublisher`. Because the buffer is
  /// shared, closing any adapter closes it for every other adapter too.
  CustomLogPublisher<Log> withParam(Param param) =>
      AsyncParamPublisher(_publish, param, flush, close);

  void _publish(Param param, Log log) => _pipeline.add((param, log));
}

/// An asynchronous publisher that batches log events along with their
/// associated parameters.
///
/// Combines the capabilities of `AsyncPublisherWithBuffer` and
/// `AsyncPublisherWithParam`, processing batches of logs where each log event
/// is paired with an auxiliary parameter for context.
///
/// Example usage:
///
/// ```dart
/// final asyncPublisher = AsyncPublisherWithBufferAndParam<String, Log>((entries, retryBuffer) async {
///   try {
///     await db.insertBatch(entries); // entries are a list of (String collectionName, Log log)
///   } catch (e) {
///     retryBuffer.addAll(entries); // Retry them next time
///   }
/// });
///
/// log.publisher = asyncPublisher.withParam(collectionName);
/// ```
final class AsyncPublisherWithBufferAndParam<Param extends Object?,
        Log extends CustomLog>
    extends AsyncPublisherWithBufferAndParamBase<Param, Log> {
  /// The function that processes a batch of buffered parameter-log entries.
  final FutureOr<void> Function(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) handler;

  /// Creates a publisher backed by [handler].
  AsyncPublisherWithBufferAndParam(
    this.handler, {
    super.sync,
    super.onError,
    super.onDropped,
    super.retryDelay,
    super.maxRetries,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) =>
      handler(entries, retryBuffer);
}

/// An asynchronous publisher that applies format transformations onto a batch
/// of parameter-log tuples before directing them to an output destination.
///
/// Supports returning unhandled parameter-log pairs during formatting, which
/// will be placed back at the front of the queue for the next batch attempt.
///
/// Example usage:
///
/// ```dart
/// final asyncFormatter = AsyncFormatterWithBufferAndParam<String, Log, Map<String, Object?>>(
///   format: (entries, retryBuffer) async {
///     // Format a batch of parameter-log tuples into a payload map
///     return {'logs': entries.map((e) => {'ctx': e.$1, 'msg': e.$2.message}).toList()};
///   },
///   output: (out, entries, retryBuffer) async {
///     try {
///       await apiClient.postLogs(out);
///     } catch (e) {
///       retryBuffer.addAll(entries); // On failure, put logs back into the retry queue
///     }
///   },
/// );
/// ```
final class AsyncFormatterWithBufferAndParam<Param extends Object?,
        Log extends CustomLog, Out extends Object?>
    extends AsyncPublisherWithBufferAndParamBase<Param, Log> {
  /// Transforms a batch of parameter-log entries into an [Out] object.
  ///
  /// Entries added to the retry buffer during formatting are excluded from
  /// the batch passed to [output] and retried with the next batch.
  ///
  /// A throwing [format] — synchronously or through its future — puts the
  /// whole batch back into the retry buffer instead of dropping it, and the
  /// error is routed to `onError` or the current zone. There is no other
  /// point at which the caller could hand the batch back: [output] never
  /// runs.
  final FutureOr<Out> Function(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) format;

  /// Receives the formatted [Out] object along with the entries it covers.
  ///
  /// Unlike [format], a throwing [output] does **not** put the batch back:
  /// by the time it runs the sink may already have taken part of the batch,
  /// so retrying wholesale would duplicate deliveries. Only what [output]
  /// itself added to the retry buffer survives; the rest is dropped and the
  /// error goes to `onError` or the current zone. Catch inside [output] and
  /// `retryBuffer.addAll(entries)` when the destination should be retried.
  final FutureOr<void> Function(
    Out out,
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) output;

  /// Creates a publisher that formats batches via [format] and hands the
  /// result to [output].
  AsyncFormatterWithBufferAndParam({
    required this.format,
    required this.output,
    super.sync,
    super.onError,
    super.onDropped,
    super.retryDelay,
    super.maxRetries,
    super.maxQueueSize,
  });

  @override
  FutureOr<void> handle(
    List<(Param, Log)> entries,
    List<(Param, Log)> retryBuffer,
  ) =>
      handleBatch(
        entries: entries,
        retryBuffer: retryBuffer,
        format: format,
        output: output,
        // The log half is matched by identity, like the buffer-only
        // formatter: a plain record map compares logs with `==`, so a user's
        // `Log` with value equality made two distinct logs interchangeable —
        // the retried one was passed to `output` *and* re-queued while the
        // other vanished.
        counter: () => HashMap<(Param, Log), int>(
          equals: (a, b) => a.$1 == b.$1 && identical(a.$2, b.$2),
          hashCode: (entry) =>
              Object.hash(entry.$1, identityHashCode(entry.$2)),
        ),
      );
}
