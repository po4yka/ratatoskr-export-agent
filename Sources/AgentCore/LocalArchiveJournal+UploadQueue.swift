import Foundation

public extension LocalArchiveJournal {
  /// Returns interrupted work to the durable queue without changing identity.
  @discardableResult
  func deferRetry(entryID: UUID, upload: UploadCheckpoint?) throws -> JournalEntry {
    lock.lock()
    defer { lock.unlock() }
    guard let previous = projection[entryID] else { throw LocalJournalError.missingEntry }
    guard previous.state == .uploading else {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: .queued)
    }
    let entry = JournalEntry(
      id: previous.id,
      fingerprint: previous.fingerprint,
      idempotencyKey: previous.idempotencyKey,
      routing: previous.routing,
      state: .queued,
      operationID: previous.operationID,
      uploadCheckpoint: upload,
      backendImport: previous.backendImport,
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
    lock.lock()
    defer { lock.unlock() }
    guard let previous = projection[entryID], previous.state == .queued,
          let checkpoint = previous.uploadCheckpoint else { throw LocalJournalError.missingEntry }
    var next = checkpoint
    next.control = control
    if control == .active {
      // A manual retry is a fresh start: the attempt and reopen budgets and the failure reason are cleared.
      next.nextRetryAt = now
      next.attemptCount = 0
      next.sessionReopens = 0
      next.failureReason = nil
    }
    return try self.checkpoint(entryID: entryID, upload: next)
  }
}
