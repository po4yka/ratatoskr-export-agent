import Foundation

extension LocalArchiveJournal {
  @discardableResult
  public func discover(
    fingerprint: ArchiveFingerprint,
    routing: ArchiveRouting,
    managedArchiveURL: URL? = nil
  ) throws -> JournalEntry {
    lock.lock()
    defer { lock.unlock() }
    guard JournalIdentity.isValid(fingerprint) else { throw LocalJournalError.invalidFingerprint }
    guard !projection.values.contains(where: { $0.fingerprint == fingerprint }) else {
      throw LocalJournalError.duplicateDigest(digestPrefix: String(fingerprint.sha256Hex.prefix(12)))
    }
    let entry = JournalEntry(
      id: UUID(), fingerprint: fingerprint,
      idempotencyKey: JournalIdentity.idempotencyKey(for: fingerprint),
      routing: routing, state: .discovered, managedArchivePath: managedArchiveURL?.path
    )
    try persist(.transition(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  @discardableResult
  public func advance(entryID: UUID, to state: JournalState) throws -> JournalEntry {
    lock.lock()
    defer { lock.unlock() }
    guard let previous = projection[entryID] else { throw LocalJournalError.missingEntry }
    guard previous.state.allowsTransition(toward: state) else {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: state)
    }
    let entry = JournalEntry(
      id: previous.id, fingerprint: previous.fingerprint,
      idempotencyKey: previous.idempotencyKey, routing: previous.routing, state: state,
      operationID: previous.operationID, uploadCheckpoint: previous.uploadCheckpoint,
      backendImport: previous.backendImport, managedArchivePath: previous.managedArchivePath
    )
    try persist(.transition(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  @discardableResult
  public func checkpoint(entryID: UUID, upload: UploadCheckpoint?) throws -> JournalEntry {
    lock.lock()
    defer { lock.unlock() }
    guard let previous = projection[entryID] else { throw LocalJournalError.missingEntry }
    guard previous.state == .queued || previous.state == .uploading else {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: previous.state)
    }
    let entry = JournalEntry(
      id: previous.id, fingerprint: previous.fingerprint,
      idempotencyKey: previous.idempotencyKey, routing: previous.routing,
      state: previous.state, operationID: previous.operationID, uploadCheckpoint: upload,
      backendImport: previous.backendImport, managedArchivePath: previous.managedArchivePath
    )
    try persist(.checkpoint(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }
}
