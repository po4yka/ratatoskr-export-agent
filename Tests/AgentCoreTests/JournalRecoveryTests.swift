import AgentCore
import CryptoKit
import Foundation
import XCTest

final class JournalRecoveryTests: XCTestCase {
  func testCrashReplayMatrixAtEveryTransitionPoint() throws {
    for checkpoint in JournalState.allCases {
      let url = recoveryJournalURL()
      let journal = try LocalArchiveJournal.open(at: url) { state in
        guard state == checkpoint else { return }
        throw SimulatedProcessKill.interrupted
      }
      XCTAssertThrowsError(try drive(journal))

      let recovered = try LocalArchiveJournal.open(at: url)
      XCTAssertEqual(recovered.entries.count, 1, "checkpoint \(checkpoint)")
      XCTAssertEqual(recovered.entries[0].state, recoveredState(after: checkpoint))
      XCTAssertEqual(
        recovered.entries[0].idempotencyKey,
        "ratatoskr-export-agent/sha256/\(recoveryFingerprint.sha256Hex)"
      )
    }
  }

  func testCorruptJournalSafeStopsWithoutChangingBytes() throws {
    for fixture in try corruptionFixtures() {
      let url = recoveryJournalURL()
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
      )
      try fixture.bytes.write(to: url)

      XCTAssertThrowsError(try LocalArchiveJournal.open(at: url)) { error in
        XCTAssertEqual(error as? LocalJournalError, .safeStop(fixture.reason))
      }
      XCTAssertEqual(try Data(contentsOf: url), fixture.bytes, fixture.name)
    }
  }

  private func drive(_ journal: LocalArchiveJournal) throws {
    var entry = try journal.discover(fingerprint: recoveryFingerprint)
    for state in [.archived, .hashed, .queued, .uploading, .uploaded, .confirmed] as [JournalState] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
  }
}

private enum SimulatedProcessKill: Error {
  case interrupted
}

private struct CorruptionFixture {
  let name: String
  let bytes: Data
  let reason: JournalCorruption
}

private let recoveryFingerprint = ArchiveFingerprint(
  sha256Hex: "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
  byteSize: 19
)

private func recoveredState(after checkpoint: JournalState) -> JournalState {
  checkpoint == .uploading ? .queued : checkpoint
}

private func recoveryJournalURL() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("recovery-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("state.journal")
}

private func corruptionFixtures() throws -> [CorruptionFixture] {
  [
    CorruptionFixture(name: "malformed", bytes: Data("not-json\n".utf8), reason: .malformedRecord),
    CorruptionFixture(name: "truncated", bytes: Data("{\"partial\":true".utf8), reason: .missingTrailingNewline),
    CorruptionFixture(
      name: "checksum", bytes: Data("{\"checksum\":\"00\",\"payloadBase64\":\"e30=\"}\n".utf8),
      reason: .checksumMismatch
    ),
    CorruptionFixture(
      name: "impossible", bytes: try impossibleTransitionRecord(), reason: .impossibleTransition
    ),
  ]
}

private func impossibleTransitionRecord() throws -> Data {
  let entry = RecoveryWireEntry(
    fingerprint: recoveryFingerprint,
    id: UUID(),
    idempotencyKey: "ratatoskr-export-agent/sha256/\(recoveryFingerprint.sha256Hex)",
    state: .archived
  )
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
  let payload = try encoder.encode(RecoveryWireRecord(entry: entry, kind: "transition"))
  let envelope = RecoveryWireEnvelope(
    checksum: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
    payloadBase64: payload.base64EncodedString()
  )
  return try encoder.encode(envelope) + Data([10])
}

private struct RecoveryWireRecord: Codable {
  let entry: RecoveryWireEntry
  let kind: String
}

private struct RecoveryWireEntry: Codable {
  let fingerprint: ArchiveFingerprint
  let id: UUID
  let idempotencyKey: String
  let state: JournalState
}

private struct RecoveryWireEnvelope: Codable {
  let checksum: String
  let payloadBase64: String
}
