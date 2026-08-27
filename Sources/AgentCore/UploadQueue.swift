import Foundation

/// Durable scheduler over journal entries; transfer state is never kept only
/// in memory and every receiver acknowledgement is checkpointed first.
public actor UploadQueue {
  let journal: LocalArchiveJournal
  let blobTransport: (any BlobReceiptTransport)?
  let operationTransport: (any PlatformArchiveOperationTransport)?
  let operationProvider: PlatformArchiveProvider?
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
    blobTransport = transport
    operationTransport = nil
    operationProvider = nil
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
    blobTransport = transport
    operationTransport = nil
    operationProvider = nil
    self.retryPolicy = retryPolicy
    limiter = UploadAdmissionLimiter(
      maximumActive: configuration.maxConcurrentUploads,
      bytesPerTick: configuration.maxUploadBytesPerSecond
    )
    chunkSize = configuration.uploadChunkBytes
  }

  /// The production archive route: Platform creates and owns a pollable import operation before
  /// the managed archive copy is streamed. A queue configured this way never sends bytes through
  /// the generic blob receipt path.
  public init(
    journal: LocalArchiveJournal,
    provider: PlatformArchiveProvider,
    operationTransport: any PlatformArchiveOperationTransport,
    configuration: AgentConfiguration,
    retryPolicy: UploadRetryPolicy = UploadRetryPolicy()
  ) {
    self.journal = journal
    blobTransport = nil
    self.operationTransport = operationTransport
    operationProvider = provider
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
