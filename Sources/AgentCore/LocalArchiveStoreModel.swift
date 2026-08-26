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
