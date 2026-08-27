import Foundation

/// The durable lifecycle of one locally preserved archive.
public enum JournalState: String, Codable, CaseIterable, Sendable {
  case discovered
  case archived
  case hashed
  case queued
  case uploading
  case uploaded
  case confirmed
}

/// Non-secret receipt-session facts required to resume an interrupted transfer.
public struct UploadCheckpoint: Codable, Equatable, Sendable {
  public enum Control: String, Codable, Sendable {
    case active
    case paused
    case cancelled
    case failed
  }

  /// An opaque receiver token, absent until the digest-first session opens.
  public let resumptionToken: String?
  public let chunkSizeBytes: Int
  public let acknowledgedIndices: Set<Int>
  public let attemptCount: Int
  public let nextRetryAt: Date?
  public let control: Control

  public init(
    resumptionToken: String? = nil,
    chunkSizeBytes: Int,
    acknowledgedIndices: Set<Int> = [],
    attemptCount: Int = 0,
    nextRetryAt: Date? = nil,
    control: Control = .active
  ) {
    self.resumptionToken = resumptionToken
    self.chunkSizeBytes = chunkSizeBytes
    self.acknowledgedIndices = acknowledgedIndices
    self.attemptCount = attemptCount
    self.nextRetryAt = nextRetryAt
    self.control = control
  }
}

/// One live entry reconstructed from the local write-ahead journal.
public struct JournalEntry: Codable, Equatable, Sendable {
  public let id: UUID
  public let fingerprint: ArchiveFingerprint
  public let idempotencyKey: String
  public let state: JournalState
  public let uploadCheckpoint: UploadCheckpoint?
  /// The last verified Platform operation fact. It contains no backend diagnostic or archive content.
  public let backendImport: BackendImportObservation?
  /// Agent-managed archive path. This local-only value is never sent or shown.
  public let managedArchivePath: String?

  public init(
    id: UUID,
    fingerprint: ArchiveFingerprint,
    idempotencyKey: String,
    state: JournalState,
    uploadCheckpoint: UploadCheckpoint? = nil,
    backendImport: BackendImportObservation? = nil,
    managedArchivePath: String? = nil
  ) {
    self.id = id
    self.fingerprint = fingerprint
    self.idempotencyKey = idempotencyKey
    self.state = state
    self.uploadCheckpoint = uploadCheckpoint
    self.backendImport = backendImport
    self.managedArchivePath = managedArchivePath
  }
}

/// A journal cannot be trusted, so the agent must stop rather than guess.
public enum LocalJournalError: Error, Equatable, Sendable {
  case duplicateDigest(digestPrefix: String)
  case missingEntry
  case invalidTransition(from: JournalState, nextState: JournalState)
  case invalidFingerprint
  case invalidMaximumBytes
  case safeStop(JournalCorruption)
}

/// The non-sensitive reason recovery refused to interpret journal bytes.
public enum JournalCorruption: Equatable, Sendable {
  case malformedRecord
  case missingTrailingNewline
  case checksumMismatch
  case impossibleTransition
}

/// Test seam invoked after a transition reaches durable storage.
public typealias JournalDurabilityHook = @Sendable (JournalState) throws -> Void

extension JournalState {
  func allowsTransition(toward nextState: JournalState) -> Bool {
    switch (self, nextState) {
    case (.discovered, .archived), (.archived, .hashed), (.hashed, .queued),
         (.queued, .uploading), (.uploading, .uploaded), (.uploaded, .confirmed):
      true
    default:
      false
    }
  }
}

enum JournalIdentity {
  static func isValid(_ fingerprint: ArchiveFingerprint) -> Bool {
    fingerprint.byteSize >= 0 && fingerprint.sha256Hex.count == 64 &&
      fingerprint.sha256Hex.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }

  static func idempotencyKey(for fingerprint: ArchiveFingerprint) -> String {
    "ratatoskr-export-agent/sha256/\(fingerprint.sha256Hex)"
  }

  static func matches(_ entry: JournalEntry) -> Bool {
    isValid(entry.fingerprint) && entry.idempotencyKey == idempotencyKey(for: entry.fingerprint) &&
      (entry.uploadCheckpoint == nil || (entry.uploadCheckpoint!.chunkSizeBytes > 0 && entry.uploadCheckpoint!.attemptCount >= 0))
  }
}
