import AgentCore
import CryptoKit
import Foundation
import XCTest

final class MixedProviderJournalRoutingTests: XCTestCase {
  func testChatGPTAndClaudeEntriesPersistDistinctRoutingFactsAfterReopen() throws {
    let journalURL = temporaryURL("mixed-routing.journal")
    let journal = try LocalArchiveJournal.open(at: journalURL)
    let chatgpt = try queuedEntry(
      in: journal,
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "a", count: 64), byteSize: 7),
      archiveName: "chatgpt.zip"
    )
    let claude = try queuedEntry(
      in: journal,
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "b", count: 64), byteSize: 8),
      archiveName: "claude.zip"
    )

    let reopened = try LocalArchiveJournal.open(at: journalURL)
    let encoded = try Dictionary(uniqueKeysWithValues: reopened.entries.map { entry in
      (entry.id, try encodedObject(entry))
    })

    let chatgptRouting = try XCTUnwrap(encoded[chatgpt.id]?["routing"] as? [String: Any])
    let claudeRouting = try XCTUnwrap(encoded[claude.id]?["routing"] as? [String: Any])
    XCTAssertEqual(chatgptRouting["provider"] as? String, "chatgpt")
    XCTAssertEqual(claudeRouting["provider"] as? String, "claude")
    XCTAssertNotNil(chatgptRouting["classification"])
    XCTAssertNotNil(claudeRouting["classification"])
    XCTAssertNotNil(chatgptRouting["archivePolicy"])
    XCTAssertNotNil(claudeRouting["archivePolicy"])
  }

  func testIncompatibleDevelopmentJournalLeavesManagedArchiveUntouched() throws {
    let root = temporaryURL("old-development-state", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let managedArchive = root.appending(path: "managed.zip")
    let original = Data("managed archive".utf8)
    try original.write(to: managedArchive)
    let journalURL = root.appending(path: "state.journal")
    try oldDevelopmentJournal(managedArchive: managedArchive, byteSize: original.count).write(to: journalURL)

    XCTAssertThrowsError(try LocalArchiveJournal.open(at: journalURL))
    XCTAssertEqual(try Data(contentsOf: managedArchive), original)
  }

  private func queuedEntry(
    in journal: LocalArchiveJournal,
    fingerprint: ArchiveFingerprint,
    archiveName: String
  ) throws -> JournalEntry {
    var entry = try journal.discover(
      fingerprint: fingerprint,
      routing: fixtureRouting(
        provider: archiveName.hasPrefix("chatgpt") ? .chatgpt : .claude,
        policy: archiveName.hasPrefix("chatgpt") ? .archiveAfterUpload : .preserveInPlace
      ),
      managedArchiveURL: temporaryURL(archiveName)
    )
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    return entry
  }

  private func encodedObject(_ entry: JournalEntry) throws -> [String: Any] {
    let data = try JSONEncoder().encode(entry)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func temporaryURL(_ name: String, isDirectory: Bool = false) -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "xpa020-\(UUID().uuidString)", directoryHint: .isDirectory)
      .appending(path: name, directoryHint: isDirectory ? .isDirectory : .notDirectory)
  }

  private func oldDevelopmentJournal(managedArchive: URL, byteSize: Int) throws -> Data {
    let fingerprint = ArchiveFingerprint(
      sha256Hex: String(repeating: "c", count: 64), byteSize: byteSize
    )
    let payload = try sortedEncoder().encode(OldRecord(
      kind: "transition",
      entry: OldEntry(
        id: UUID(), fingerprint: fingerprint,
        idempotencyKey: "ratatoskr-export-agent/sha256/\(fingerprint.sha256Hex)",
        state: .discovered, managedArchivePath: managedArchive.path
      )
    ))
    let checksum = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    return try sortedEncoder().encode(OldEnvelope(
      checksum: checksum, payloadBase64: payload.base64EncodedString()
    )) + Data([10])
  }

  private func sortedEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
}

private struct OldRecord: Encodable { let kind: String; let entry: OldEntry }
private struct OldEnvelope: Encodable { let checksum: String; let payloadBase64: String }
private struct OldEntry: Encodable {
  let id: UUID
  let fingerprint: ArchiveFingerprint
  let idempotencyKey: String
  let state: JournalState
  let managedArchivePath: String
}
