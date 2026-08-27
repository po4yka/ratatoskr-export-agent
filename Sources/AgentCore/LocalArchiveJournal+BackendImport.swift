import Foundation

public extension LocalArchiveJournal {
  /// Durably binds an already accepted Platform operation to an archive entry.
  @discardableResult
  func bindBackendOperation(entryID: UUID, operationID: UUID) throws -> JournalEntry {
    guard let previous = projection[entryID] else { throw LocalJournalError.missingEntry }
    guard previous.state != .discovered else {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: previous.state)
    }
    if let observed = previous.backendImport, observed.operationID != operationID {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: previous.state)
    }
    let entry = JournalEntry(
      id: previous.id, fingerprint: previous.fingerprint, idempotencyKey: previous.idempotencyKey,
      state: previous.state, uploadCheckpoint: previous.uploadCheckpoint,
      backendImport: previous.backendImport ?? BackendImportObservation(
        operationID: operationID, presentation: .processing, observedAt: .distantPast
      ),
      managedArchivePath: previous.managedArchivePath
    )
    try persist(.backendObservation(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  /// Records the newest successfully decoded Platform operation fact.
  @discardableResult
  func recordBackendObservation(
    entryID: UUID,
    operationID: UUID,
    presentation: BackendImportPresentation,
    observedAt: Date,
    backendUpdatedAt: Date? = nil
  ) throws -> JournalEntry {
    guard let previous = projection[entryID] else { throw LocalJournalError.missingEntry }
    guard previous.backendImport?.operationID == operationID else { throw LocalJournalError.missingEntry }
    let delivered = previous.backendImport?.terminalNoticeDelivered ?? false
    let entry = JournalEntry(
      id: previous.id, fingerprint: previous.fingerprint, idempotencyKey: previous.idempotencyKey,
      state: previous.state, uploadCheckpoint: previous.uploadCheckpoint,
      backendImport: BackendImportObservation(
        operationID: operationID, presentation: presentation, observedAt: observedAt,
        backendUpdatedAt: backendUpdatedAt,
        terminalNoticeDelivered: delivered
      ),
      managedArchivePath: previous.managedArchivePath
    )
    try persist(.backendObservation(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  /// Records delivery only after the operating system accepted a generic terminal notice.
  @discardableResult
  func markBackendTerminalNoticeDelivered(entryID: UUID, operationID: UUID) throws -> JournalEntry {
    guard let previous = projection[entryID], let observation = previous.backendImport,
          observation.operationID == operationID, observation.presentation.isTerminal
    else { throw LocalJournalError.missingEntry }
    let entry = JournalEntry(
      id: previous.id, fingerprint: previous.fingerprint, idempotencyKey: previous.idempotencyKey,
      state: previous.state, uploadCheckpoint: previous.uploadCheckpoint,
      backendImport: BackendImportObservation(
        operationID: observation.operationID, presentation: observation.presentation,
        observedAt: observation.observedAt, backendUpdatedAt: observation.backendUpdatedAt,
        terminalNoticeDelivered: true
      ), managedArchivePath: previous.managedArchivePath
    )
    try persist(.backendObservation(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }
}
