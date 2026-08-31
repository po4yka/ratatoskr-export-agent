import Foundation

extension UploadQueue {
  func recordFailure(entryID: UUID, error: Error, now: Date) async {
    guard let current = journal.entries.first(where: { $0.id == entryID }),
          current.state == .uploading else { return }
    let checkpoint = current.uploadCheckpoint ?? UploadCheckpoint(chunkSizeBytes: chunkSize)
    let next = retryCheckpoint(for: error, from: checkpoint, at: now)
    _ = try? journal.deferRetry(entryID: entryID, upload: next)
    publishStatus()
  }

  func retryCheckpoint(for error: Error, from checkpoint: UploadCheckpoint, at now: Date) -> UploadCheckpoint {
    switch error {
    case BlobReceiptTransportError.unavailable, PlatformDeviceTransportError.unavailable:
      return retryCheckpoint(from: checkpoint, at: now)
    case let BlobReceiptTransportError.retryAfter(retryAfter):
      return retryCheckpoint(from: checkpoint, at: now, retryAfter: retryAfter)
    case BlobReceiptTransportError.expiredSession:
      let attempt = checkpoint.attemptCount + 1
      return UploadCheckpoint(
        chunkSizeBytes: chunkSize,
        attemptCount: attempt,
        nextRetryAt: retryPolicy.nextEligible(at: now, attempt: attempt)
      )
    case BlobReceiptTransportError.capacityUnavailable:
      return UploadCheckpoint(
        resumptionToken: checkpoint.resumptionToken,
        chunkSizeBytes: checkpoint.chunkSizeBytes,
        acknowledgedIndices: checkpoint.acknowledgedIndices,
        attemptCount: checkpoint.attemptCount,
        nextRetryAt: now
      )
    default:
      return UploadCheckpoint(
        resumptionToken: checkpoint.resumptionToken,
        chunkSizeBytes: checkpoint.chunkSizeBytes,
        acknowledgedIndices: checkpoint.acknowledgedIndices,
        attemptCount: checkpoint.attemptCount,
        control: .failed
      )
    }
  }

  func retryCheckpoint(
    from checkpoint: UploadCheckpoint,
    at now: Date,
    retryAfter: TimeInterval? = nil
  ) -> UploadCheckpoint {
    let attempt = checkpoint.attemptCount + 1
    return UploadCheckpoint(
      resumptionToken: checkpoint.resumptionToken,
      chunkSizeBytes: checkpoint.chunkSizeBytes,
      acknowledgedIndices: checkpoint.acknowledgedIndices,
      attemptCount: attempt,
      nextRetryAt: retryPolicy.nextEligible(at: now, attempt: attempt, retryAfter: retryAfter)
    )
  }

  func ensureCheckpoint(entryID: UUID, now: Date) throws {
    guard let entry = journal.entries.first(where: { $0.id == entryID }) else {
      throw LocalJournalError.missingEntry
    }
    guard entry.state == .queued else {
      throw LocalJournalError.invalidTransition(from: entry.state, nextState: entry.state)
    }
    guard entry.uploadCheckpoint == nil else { return }
    _ = try journal.checkpoint(
      entryID: entryID,
      upload: UploadCheckpoint(chunkSizeBytes: chunkSize, nextRetryAt: now)
    )
  }

  func isEligible(_ entry: JournalEntry, at now: Date) -> Bool {
    guard entry.state == .queued, let path = entry.managedArchivePath, !path.isEmpty else {
      return false
    }
    // A returned operation ID is a durable recovery key. Do not create or send a second upload
    // while its authoritative Platform result can still be polled.
    guard entry.backendImport?.presentation.isTerminal != true else { return false }
    guard (entry.uploadCheckpoint?.control ?? .active) == .active else { return false }
    return (entry.uploadCheckpoint?.nextRetryAt ?? .distantPast) <= now
  }
}
