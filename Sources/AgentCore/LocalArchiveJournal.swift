import Foundation

/// Append-only local state for preserved archive work. Every successful
/// mutation is synchronized before it becomes observable from this instance.
public final class LocalArchiveJournal {
  let url: URL
  let maximumBytes: Int
  let didDurablyWrite: JournalDurabilityHook
  var projection: [UUID: JournalEntry]

  private init(
    url: URL,
    maximumBytes: Int,
    projection: [UUID: JournalEntry],
    didDurablyWrite: @escaping JournalDurabilityHook
  ) {
    self.url = url
    self.maximumBytes = maximumBytes
    self.projection = projection
    self.didDurablyWrite = didDurablyWrite
  }

  /// Opens a journal and reconstructs its last valid projection.
  public static func open(
    at url: URL,
    maximumBytes: Int = 1_048_576,
    didDurablyWrite: @escaping JournalDurabilityHook = { _ in }
  ) throws -> LocalArchiveJournal {
    guard maximumBytes >= 1024 else { throw LocalJournalError.invalidMaximumBytes }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let journal = LocalArchiveJournal(
      url: url,
      maximumBytes: maximumBytes,
      projection: try JournalFile.readProjection(at: url),
      didDurablyWrite: didDurablyWrite
    )
    try journal.recoverInterruptedUploads()
    return journal
  }

  /// The stable, deterministic view of every active archive entry.
  public var entries: [JournalEntry] {
    projection.values.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  /// Starts tracking a unique archive digest in the discovered state.
  @discardableResult
  public func discover(fingerprint: ArchiveFingerprint, managedArchiveURL: URL? = nil) throws -> JournalEntry {
    guard JournalIdentity.isValid(fingerprint) else {
      throw LocalJournalError.invalidFingerprint
    }
    guard !projection.values.contains(where: { $0.fingerprint == fingerprint }) else {
      throw LocalJournalError.duplicateDigest(digestPrefix: String(fingerprint.sha256Hex.prefix(12)))
    }
    let entry = JournalEntry(
      id: UUID(),
      fingerprint: fingerprint,
      idempotencyKey: JournalIdentity.idempotencyKey(for: fingerprint),
      state: .discovered,
      managedArchivePath: managedArchiveURL?.path
    )
    try persist(.transition(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  /// Advances one entry along the only accepted archive lifecycle.
  @discardableResult
  public func advance(entryID: UUID, to state: JournalState) throws -> JournalEntry {
    guard let previous = projection[entryID] else {
      throw LocalJournalError.missingEntry
    }
    guard previous.state.allowsTransition(toward: state) else {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: state)
    }
    let entry = JournalEntry(
      id: previous.id,
      fingerprint: previous.fingerprint,
      idempotencyKey: previous.idempotencyKey,
      state: state,
      uploadCheckpoint: previous.uploadCheckpoint,
      backendImport: previous.backendImport,
      managedArchivePath: previous.managedArchivePath
    )
    try persist(.transition(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  /// Persists receipt-session facts without changing the lifecycle state.
  @discardableResult
  public func checkpoint(entryID: UUID, upload: UploadCheckpoint?) throws -> JournalEntry {
    guard let previous = projection[entryID] else { throw LocalJournalError.missingEntry }
    guard previous.state == .queued || previous.state == .uploading else {
      throw LocalJournalError.invalidTransition(from: previous.state, nextState: previous.state)
    }
    let entry = JournalEntry(
      id: previous.id, fingerprint: previous.fingerprint,
      idempotencyKey: previous.idempotencyKey, state: previous.state, uploadCheckpoint: upload,
      backendImport: previous.backendImport,
      managedArchivePath: previous.managedArchivePath
    )
    try persist(.checkpoint(entry))
    projection[entry.id] = entry
    try compactIfNeeded()
    return entry
  }

  func persist(_ record: JournalRecord) throws {
    try JournalFile.append(record, to: url)
    if let entry = record.entry {
      try didDurablyWrite(entry.state)
    }
  }

  private func recoverInterruptedUploads() throws {
    for entry in entries where entry.state == .uploading {
      let recovered = JournalEntry(
        id: entry.id,
        fingerprint: entry.fingerprint,
        idempotencyKey: entry.idempotencyKey,
        state: .queued,
        uploadCheckpoint: entry.uploadCheckpoint,
        backendImport: entry.backendImport,
        managedArchivePath: entry.managedArchivePath
      )
      try persist(.recovery(recovered))
      projection[entry.id] = recovered
      try compactIfNeeded()
    }
  }

  func compactIfNeeded() throws {
    try JournalFile.compact(projection, at: url, maximumBytes: maximumBytes)
  }
}
