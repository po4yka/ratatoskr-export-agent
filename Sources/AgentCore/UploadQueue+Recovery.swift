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
    var next = checkpoint
    switch error {
    case BlobReceiptTransportError.unavailable, PlatformDeviceTransportError.unavailable:
      return retryCheckpoint(from: checkpoint, at: now)
    case let BlobReceiptTransportError.retryAfter(retryAfter):
      return retryCheckpoint(from: checkpoint, at: now, retryAfter: retryAfter)
    case BlobReceiptTransportError.expiredSession:
      return reopenCheckpoint(from: checkpoint, at: now)
    case BlobReceiptTransportError.capacityUnavailable:
      next.nextRetryAt = now
    default:
      next.control = .failed
      next.nextRetryAt = nil
    }
    return next
  }

  func retryCheckpoint(
    from checkpoint: UploadCheckpoint,
    at now: Date,
    retryAfter: TimeInterval? = nil
  ) -> UploadCheckpoint {
    var next = checkpoint
    next.attemptCount += 1
    if next.attemptCount > retryPolicy.maximumAttempts {
      next.control = .failed
      next.failureReason = .retriesExhausted
      next.nextRetryAt = nil
    } else {
      next.nextRetryAt = retryPolicy.nextEligible(at: now, attempt: next.attemptCount, retryAfter: retryAfter)
    }
    return next
  }

  /// Platform dropped the session (404 on status, chunk or finalize): forget the token and the acknowledged chunks so
  /// the next run opens a new session, at most `maxSessionReopens` times per entry (XR-021 CONTRACTS.md R5-05 rule 2).
  func reopenCheckpoint(from checkpoint: UploadCheckpoint, at now: Date) -> UploadCheckpoint {
    var next = checkpoint
    next.resumptionToken = nil
    next.acknowledgedIndices = []
    next.chunkSizeBytes = chunkSize
    next.sessionReopens += 1
    next.attemptCount += 1
    if next.sessionReopens > maxSessionReopens {
      next.control = .failed
      next.failureReason = .sessionExpired
      next.nextRetryAt = nil
    } else {
      next.nextRetryAt = retryPolicy.nextEligible(at: now, attempt: next.attemptCount)
    }
    return next
  }

  /// The idempotency key of the next session open: the journal key for the first session, a distinct key per reopen
  /// so Platform mints a new session instead of replaying the dead one.
  func openIdempotencyKey(for entry: JournalEntry) -> String {
    let reopens = entry.uploadCheckpoint?.sessionReopens ?? 0
    return reopens == 0 ? entry.idempotencyKey : "\(entry.idempotencyKey)/session-\(reopens)"
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
