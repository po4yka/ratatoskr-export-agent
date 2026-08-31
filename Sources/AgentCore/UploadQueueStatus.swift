import Foundation

/// One actionable upload projection. It deliberately excludes archive paths,
/// fingerprints, idempotency keys, and receiver tokens.
public struct UploadQueueItemStatus: Equatable, Sendable {
  public let id: UUID
  public let title: String
  public let canPause: Bool
  public let canRetry: Bool
  public let canCancel: Bool
}

/// Privacy-safe projection used by UI surfaces; it never contains paths or digests.
public struct UploadQueueStatus: Equatable, Sendable {
  public let activeCount: Int
  public let activeCompletedBytes: Int
  public let activeTotalBytes: Int
  public let queuedCount: Int
  public let pausedCount: Int
  public let retryingCount: Int
  public let failedCount: Int
  public let items: [UploadQueueItemStatus]

  public init(entries: [JournalEntry], now: Date = Date()) {
    let activeEntries = entries.filter { $0.state == .uploading }
    activeCount = activeEntries.count
    activeCompletedBytes = activeEntries.reduce(0) { partial, entry in
      partial + Self.acknowledgedBytes(for: entry)
    }
    activeTotalBytes = activeEntries.reduce(0) { $0 + $1.fingerprint.byteSize }
    pausedCount = entries.filter { $0.uploadCheckpoint?.control == .paused }.count
    failedCount = entries.filter { $0.uploadCheckpoint?.control == .failed }.count
    queuedCount =
      entries.filter {
        $0.state == .queued && ($0.uploadCheckpoint?.control ?? .active) == .active
      }.count
    retryingCount =
      entries.filter {
        $0.state == .queued && ($0.uploadCheckpoint?.control ?? .active) == .active
          && ($0.uploadCheckpoint?.nextRetryAt ?? now) > now
      }.count
    items = entries.compactMap { entry in
      guard entry.state == .queued else { return nil }
      let control = entry.uploadCheckpoint?.control ?? .active
      guard control != .cancelled else { return nil }
      return UploadQueueItemStatus(
        id: entry.id,
        title: control == .active ? "Queued archive" : "Paused archive",
        canPause: control == .active,
        canRetry: control == .paused || control == .failed,
        canCancel: true
      )
    }
  }

  public var menuTitle: String {
    if activeCount > 0 {
      let percent = activeTotalBytes == 0 ? 0 : activeCompletedBytes * 100 / activeTotalBytes
      return "Uploading \(activeCount) archive\(activeCount == 1 ? "" : "s") (\(percent)%)"
    }
    if retryingCount > 0 {
      return "\(retryingCount) upload retry queued"
    }
    if pausedCount > 0 {
      return "\(pausedCount) upload\(pausedCount == 1 ? "" : "s") paused"
    }
    if failedCount > 0 {
      return "\(failedCount) upload\(failedCount == 1 ? "" : "s") need attention"
    }
    return queuedCount > 0
      ? "\(queuedCount) upload\(queuedCount == 1 ? "" : "s") queued" : "No uploads queued"
  }

  private static func acknowledgedBytes(for entry: JournalEntry) -> Int {
    guard let checkpoint = entry.uploadCheckpoint else { return 0 }
    return checkpoint.acknowledgedIndices.reduce(0) { partial, index in
      guard index >= 0 else { return partial }
      let offset = index * checkpoint.chunkSizeBytes
      guard offset < entry.fingerprint.byteSize else { return partial }
      return partial + min(checkpoint.chunkSizeBytes, entry.fingerprint.byteSize - offset)
    }
  }
}
