import CryptoKit
import Foundation

/// Where a staged copy will be published once its digest is known.
struct ArchivePublicationLayout: Sendable {
  let monthDirectory: URL
  let container: ArchiveContainer
  let providerSegment: String
}

// Staging, verification, and atomic publication of preserved copies.
extension LocalArchiveStore {
  /// Stages a verified copy and publishes it atomically, or recognizes an
  /// identical stored entry write-once.
  func publish(
    sourceAt source: URL,
    observedByteSize: Int,
    layout: ArchivePublicationLayout,
    publishHook: @Sendable (PublishCheckpoint) throws -> Void
  ) throws -> LocalArchiveRecord {
    let temporaryURL =
      layout.monthDirectory
      .appendingPathComponent("\(Self.temporaryPrefix)\(UUID().uuidString)")
    do {
      let fingerprint = try stageCopy(
        sourceAt: source,
        to: temporaryURL,
        expectedByteCount: observedByteSize,
        publishHook: publishHook
      )
      let finalURL = layout.monthDirectory.appendingPathComponent(
        "\(fingerprint.sha256Hex)\(Self.extensionName(for: layout.container))"
      )
      if FileManager.default.fileExists(atPath: finalURL.path) {
        return try adoptStoredEntry(
          at: finalURL,
          expectedDigest: fingerprint.sha256Hex,
          providerSegment: layout.providerSegment,
          staged: temporaryURL
        )
      }
      try publishHook(.beforeRename)
      try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
      return LocalArchiveRecord(
        url: finalURL,
        fingerprint: fingerprint,
        providerSegment: layout.providerSegment,
        reusedExistingEntry: false
      )
    } catch {
      try? FileManager.default.removeItem(atPath: temporaryURL.path)
      throw error
    }
  }

  /// Streams the source into the staging file while hashing, then verifies
  /// the staged byte count against what was hashed before anyone can see it.
  func stageCopy(
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

  func verifyStaged(
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
  func adoptStoredEntry(
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
}
