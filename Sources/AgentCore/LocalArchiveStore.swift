import CryptoKit
import Foundation

/// The agent-owned immutable archive store. Content-addressed and
/// write-once: every publication stages into a `.ratatoskr-tmp-` file inside
/// the destination directory and publishes with one same-volume rename, so
/// no partial state ever appears under a final name.
public struct LocalArchiveStore: Sendable {
  /// Prefix reserved for staged copies awaiting publication or sweeping.
  public static let temporaryPrefix = ".ratatoskr-tmp-"

  /// Root of the agent-managed store.
  public let root: URL

  /// Maximum total regular-file byte count the store may hold.
  public let maxStoreBytes: Int

  let hasher: StreamingHasher
  private let staleTemporaryAge: TimeInterval = 3_600

  public init(root: URL, maxStoreBytes: Int, hasher: StreamingHasher = StreamingHasher()) {
    self.root = root
    self.maxStoreBytes = maxStoreBytes
    self.hasher = hasher
  }

  /// Preserves the candidate's exact bytes into the store, refusing up
  /// front when the budget would be exceeded, recognizing stored digests
  /// write-once, and never displacing foreign content. `observedByteSize`
  /// is the stable snapshot size; `classification` picks layout segments;
  /// `archivedOn` anchors the year/month layout; `publishHook` observes or
  /// interrupts publication at its checkpoints.
  public func archive(
    sourceAt source: URL,
    observedByteSize: Int,
    classification: ArchiveClassification,
    archivedOn date: Date = Date(),
    publishHook: @Sendable @escaping (PublishCheckpoint) throws -> Void = { _ in }
  ) throws -> LocalArchiveRecord {
    let currentBytes = try Self.totalStoredBytes(under: root)
    guard currentBytes + observedByteSize <= maxStoreBytes else {
      throw LocalArchiveStoreError.overBudget(
        currentBytes: currentBytes,
        incomingBytes: observedByteSize,
        limitBytes: maxStoreBytes
      )
    }
    let segment = Self.segmentName(for: classification.provider)
    let monthDirectory = Self.monthDirectory(
      providerSegment: segment, calendarAnchor: date, root: root
    )
    try FileManager.default.createDirectory(at: monthDirectory, withIntermediateDirectories: true)
    sweepStaleTemporaries(
      in: monthDirectory,
      olderThan: Date().addingTimeInterval(-staleTemporaryAge)
    )
    return try publish(
      sourceAt: source,
      observedByteSize: observedByteSize,
      layout: ArchivePublicationLayout(
        monthDirectory: monthDirectory,
        container: classification.container,
        providerSegment: segment
      ),
      publishHook: publishHook
    )
  }

}
