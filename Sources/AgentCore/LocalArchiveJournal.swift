import Foundation

/// Append-only local state for preserved archive work. Every successful
/// mutation is synchronized before it becomes observable from this instance.
public final class LocalArchiveJournal: @unchecked Sendable {
  let url: URL
  let maximumBytes: Int
  let didDurablyWrite: JournalDurabilityHook
  var projection: [UUID: JournalEntry]
  let lock = NSRecursiveLock()

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
    lock.lock()
    defer { lock.unlock() }
    return projection.values.sorted { $0.id.uuidString < $1.id.uuidString }
  }

  func persist(_ record: JournalRecord) throws {
    lock.lock()
    defer { lock.unlock() }
    try JournalFile.append(record, to: url)
    if let entry = record.entry {
      try didDurablyWrite(entry.state)
    }
  }

  private func recoverInterruptedUploads() throws {
    lock.lock()
    defer { lock.unlock() }
    for entry in entries where entry.state == .uploading {
      let recovered = JournalEntry(
        id: entry.id,
        fingerprint: entry.fingerprint,
        idempotencyKey: entry.idempotencyKey,
        routing: entry.routing,
        state: .queued,
        operationID: entry.operationID,
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
    lock.lock()
    defer { lock.unlock() }
    try JournalFile.compact(projection, at: url, maximumBytes: maximumBytes)
  }
}
