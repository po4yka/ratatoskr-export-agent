import Foundation

public extension LocalArchiveJournal {
  /// Returns interrupted work to the durable queue without changing identity.
  @discardableResult
  func deferRetry(entryID: UUID, upload: UploadCheckpoint?) throws -> JournalEntry {
    guard let previous = projection[entryID] else { throw LocalJournalError.missingEntry }
    guard previous.state == .uploading else {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: .queued)
    }
    let entry = JournalEntry(
      id: previous.id,
      fingerprint: previous.fingerprint,
      idempotencyKey: previous.idempotencyKey,
      state: .queued,
      uploadCheckpoint: upload,
      managedArchivePath: previous.managedArchivePath
    )
    try persist(.recovery(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  /// Makes a queued entry user-paused, cancelled, or immediately eligible.
  @discardableResult
  func controlRetry(
    entryID: UUID,
    control: UploadCheckpoint.Control,
    now: Date = Date()
  ) throws -> JournalEntry {
    guard let previous = projection[entryID], previous.state == .queued,
          let checkpoint = previous.uploadCheckpoint else { throw LocalJournalError.missingEntry }
    let retryAt = control == .active ? now : checkpoint.nextRetryAt
    return try self.checkpoint(
      entryID: entryID,
      upload: UploadCheckpoint(
        resumptionToken: checkpoint.resumptionToken,
        chunkSizeBytes: checkpoint.chunkSizeBytes,
        acknowledgedIndices: checkpoint.acknowledgedIndices,
        attemptCount: checkpoint.attemptCount,
        nextRetryAt: retryAt,
        control: control
      )
    )
  }
}
