import Foundation

/// Durable scheduler over journal entries; transfer state is never kept only
/// in memory and every receiver acknowledgement is checkpointed first.
public actor UploadQueue {
  let journal: LocalArchiveJournal
  let transport: any BlobReceiptTransport
  let retryPolicy: UploadRetryPolicy
  let limiter: UploadAdmissionLimiter
  let chunkSize: Int
  var statusContinuations: [UUID: AsyncStream<UploadQueueStatus>.Continuation] = [:]

  public init(
    journal: LocalArchiveJournal,
    transport: any BlobReceiptTransport,
    retryPolicy: UploadRetryPolicy,
    limiter: UploadAdmissionLimiter,
    chunkSize: Int
  ) {
    self.journal = journal
    self.transport = transport
    self.retryPolicy = retryPolicy
    self.limiter = limiter
    self.chunkSize = chunkSize
  }

  /// Uses the validated version-1 transfer caps as the sole queue budget.
  public init(
    journal: LocalArchiveJournal,
    transport: any BlobReceiptTransport,
    configuration: AgentConfiguration,
    retryPolicy: UploadRetryPolicy = UploadRetryPolicy()
  ) {
    self.journal = journal
    self.transport = transport
    self.retryPolicy = retryPolicy
    limiter = UploadAdmissionLimiter(
      maximumActive: configuration.maxConcurrentUploads,
      bytesPerTick: configuration.maxUploadBytesPerSecond
    )
    chunkSize = configuration.uploadChunkBytes
  }

  /// Returns the durable projection through the queue actor's isolation.
  public func entries() -> [JournalEntry] {
    journal.entries
  }

  public func status() -> UploadQueueStatus {
    UploadQueueStatus(entries: journal.entries)
  }

  /// Emits only redacted journal projections; the UI never observes paths or
  /// receipt tokens directly.
  public func statusUpdates() -> AsyncStream<UploadQueueStatus> {
    let id = UUID()
    let initial = UploadQueueStatus(entries: journal.entries)
    return AsyncStream { continuation in
      statusContinuations[id] = continuation
      continuation.yield(initial)
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeStatusContinuation(id) }
      }
    }
  }

  public func pause(entryID: UUID, now: Date = Date()) throws {
    try ensureCheckpoint(entryID: entryID, now: now)
    _ = try journal.controlRetry(entryID: entryID, control: .paused, now: now)
    publishStatus()
  }

  public func cancel(entryID: UUID, now: Date = Date()) throws {
    try ensureCheckpoint(entryID: entryID, now: now)
    _ = try journal.controlRetry(entryID: entryID, control: .cancelled, now: now)
    publishStatus()
  }

  public func retryNow(entryID: UUID, now: Date = Date()) throws {
    try ensureCheckpoint(entryID: entryID, now: now)
    _ = try journal.controlRetry(entryID: entryID, control: .active, now: now)
    publishStatus()
  }
}
