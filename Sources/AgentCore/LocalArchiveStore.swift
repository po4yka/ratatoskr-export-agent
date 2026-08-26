import CryptoKit
import Foundation

/// Where a publication has reached, handed to the publish hook so callers
/// (and tests) can observe or interrupt progress at exact points.
public enum PublishCheckpoint: Equatable, Sendable {
  /// A chunk was written to the temporary file; payload counts bytes flushed.
  case afterChunkFlush(Int)

  /// The temporary file is complete and verified; the rename is next.
  case beforeRename
}

/// Why preserving a candidate into the store ended without publication.
public enum LocalArchiveStoreError: Error, Equatable, Sendable {
  /// Current stored bytes plus the incoming archive would exceed the limit.
  case overBudget(currentBytes: Int, incomingBytes: Int, limitBytes: Int)

  /// A file already occupies the digest-addressed path with other content;
  /// the store never displaces existing bytes.
  case occupiedDigestMismatch(digestPrefix: String)

  /// The source vanished or shrank below its observed size during archival,
  /// or the staged copy could not be completed and verified.
  case sourceUnavailableDuringCopy
}

/// One completed preservation: where the archive lives and how it was
/// identified.
public struct LocalArchiveRecord: Equatable, Sendable {
  /// Final store path of the preserved original bytes.
  public let url: URL

  /// Content identity of the preserved bytes.
  public let fingerprint: ArchiveFingerprint

  /// Store segment carrying the advisory provider label.
  public let providerSegment: String

  /// True when a previously stored copy with this digest was reused.
  public let reusedExistingEntry: Bool

  public init(
    url: URL,
    fingerprint: ArchiveFingerprint,
    providerSegment: String,
    reusedExistingEntry: Bool
  ) {
    self.url = url
    self.fingerprint = fingerprint
    self.providerSegment = providerSegment
    self.reusedExistingEntry = reusedExistingEntry
  }
}

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

  private let hasher: StreamingHasher
  private let staleTemporaryAge: TimeInterval = 3_600

  public init(root: URL, maxStoreBytes: Int, hasher: StreamingHasher = StreamingHasher()) {
    self.root = root
    self.maxStoreBytes = maxStoreBytes
    self.hasher = hasher
  }

  /// Sums regular-file bytes under the given directory, recursively.
  public static func totalStoredBytes(under root: URL) throws -> Int {
    guard FileManager.default.fileExists(atPath: root.path) else {
      return 0
    }
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
    var total = 0
    while let url = enumerator?.nextObject() as? URL {
      let values = try? url.resourceValues(forKeys: Set(keys))
      if values?.isRegularFile == true {
        total += values?.fileSize ?? 0
      }
    }
    return total
  }

  /// Preserves the candidate's exact bytes into the store. Refuses up front
  /// when the configured budget would be exceeded, recognizes already-stored
  /// digests write-once, and never displaces foreign content.
  ///
  /// - Parameters:
  ///   - observedByteSize: The stable snapshot size the pipeline recorded.
  ///   - classification: Advisory label deciding the store layout segments.
  ///   - archivedOn: Calendar anchor for the year/month layout.
  ///   - publishHook: Observation/interruption seam around publication.
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
      container: classification.container,
      providerSegment: segment,
      in: monthDirectory,
      publishHook: publishHook
    )
  }

  /// Stages a verified copy and publishes it atomically, or recognizes an
  /// identical stored entry write-once.
  private func publish(
    sourceAt source: URL,
    observedByteSize: Int,
    container: ArchiveContainer,
    providerSegment: String,
    in monthDirectory: URL,
    publishHook: @Sendable (PublishCheckpoint) throws -> Void
  ) throws -> LocalArchiveRecord {
    let temporaryURL =
      monthDirectory
      .appendingPathComponent("\(Self.temporaryPrefix)\(UUID().uuidString)")
    do {
      let fingerprint = try stageCopy(
        sourceAt: source,
        to: temporaryURL,
        expectedByteCount: observedByteSize,
        publishHook: publishHook
      )
      let finalURL = monthDirectory.appendingPathComponent(
        "\(fingerprint.sha256Hex)\(Self.extensionName(for: container))"
      )
      if FileManager.default.fileExists(atPath: finalURL.path) {
        return try adoptStoredEntry(
          at: finalURL,
          expectedDigest: fingerprint.sha256Hex,
          providerSegment: providerSegment,
          staged: temporaryURL
        )
      }
      try publishHook(.beforeRename)
      try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
      return LocalArchiveRecord(
        url: finalURL,
        fingerprint: fingerprint,
        providerSegment: providerSegment,
        reusedExistingEntry: false
      )
    } catch {
      try? FileManager.default.removeItem(atPath: temporaryURL.path)
      throw error
    }
  }

  /// Streams the source into the staging file while hashing, then verifies
  /// the staged byte count against what was hashed before anyone can see it.
  private func stageCopy(
    sourceAt source: URL,
    to temporaryURL: URL,
    expectedByteCount: Int,
    publishHook: @Sendable (PublishCheckpoint) throws -> Void
  ) throws -> ArchiveFingerprint {
    FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
    let reader = try FileHandle(forReadingFrom: source)
    defer {
      try? reader.close()
    }
    let writer = try FileHandle(forWritingTo: temporaryURL)
    defer {
      try? writer.close()
    }
    var hasherState = SHA256()
    var consumed = 0
    while consumed < expectedByteCount {
      let wanted = min(hasher.chunkSize, expectedByteCount - consumed)
      guard let chunk = try reader.read(upToCount: wanted), !chunk.isEmpty else {
        throw LocalArchiveStoreError.sourceUnavailableDuringCopy
      }
      try writer.write(contentsOf: chunk)
      hasherState.update(data: chunk)
      consumed += chunk.count
      try publishHook(.afterChunkFlush(consumed))
    }
    return try verifyStaged(temporaryURL, consumed: consumed, hasherState: hasherState)
  }

  private func verifyStaged(
    _ temporaryURL: URL,
    consumed: Int,
    hasherState: SHA256
  ) throws -> ArchiveFingerprint {
    let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
    let stagedSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard Int(stagedSize) == consumed else {
      throw LocalArchiveStoreError.sourceUnavailableDuringCopy
    }
    return ArchiveFingerprint(
      sha256Hex: hasherState.finalize().map { String(format: "%02x", $0) }.joined(),
      byteSize: consumed
    )
  }

  /// Occupied-path handling: an identical stored digest is adopted
  /// write-once; foreign content is refused without displacing it.
  private func adoptStoredEntry(
    at storedURL: URL,
    expectedDigest: String,
    providerSegment: String,
    staged: URL
  ) throws -> LocalArchiveRecord {
    try? FileManager.default.removeItem(atPath: staged.path)
    let storedFingerprint = try hasher.fingerprint(at: storedURL)
    guard storedFingerprint.sha256Hex == expectedDigest else {
      throw LocalArchiveStoreError.occupiedDigestMismatch(
        digestPrefix: String(expectedDigest.prefix(12))
      )
    }
    return LocalArchiveRecord(
      url: storedURL,
      fingerprint: storedFingerprint,
      providerSegment: providerSegment,
      reusedExistingEntry: true
    )
  }

  /// Removes temporaries abandoned by earlier terminated publications while
  /// leaving anything recent enough to belong to a live publication alone.
  private func sweepStaleTemporaries(in directory: URL, olderThan cutoff: Date) {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
      )) ?? []
    for entry in entries where entry.lastPathComponent.hasPrefix(Self.temporaryPrefix) {
      let modified =
        (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      if modified < cutoff {
        try? FileManager.default.removeItem(at: entry)
      }
    }
  }

  private static func monthDirectory(
    providerSegment: String,
    calendarAnchor date: Date,
    root: URL
  ) -> URL {
    let components = Calendar.current.dateComponents([.year, .month], from: date)
    return
      root
      .appendingPathComponent(providerSegment, isDirectory: true)
      .appendingPathComponent(String(components.year ?? 0), isDirectory: true)
      .appendingPathComponent(String(format: "%02d", components.month ?? 0), isDirectory: true)
  }

  private static func segmentName(for provider: ArchiveProviderHint) -> String {
    switch provider {
    case .chatgpt:
      "chatgpt"
    case .claude:
      "claude"
    case .instagram:
      "instagram"
    case .threads:
      "threads"
    case .unidentified:
      "unidentified"
    }
  }

  private static func extensionName(for container: ArchiveContainer) -> String {
    switch container {
    case .zip:
      ".zip"
    case .json:
      ".json"
    case .unknown:
      ".bin"
    }
  }
}
