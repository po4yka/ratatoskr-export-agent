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

/// One live entry reconstructed from the local write-ahead journal.
public struct JournalEntry: Codable, Equatable, Sendable {
  public let id: UUID
  public let fingerprint: ArchiveFingerprint
  public let idempotencyKey: String
  public let state: JournalState
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
    isValid(entry.fingerprint) && entry.idempotencyKey == idempotencyKey(for: entry.fingerprint)
  }
}
