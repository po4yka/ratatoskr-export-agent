import AgentCore
import Foundation
import XCTest

final class UploadJournalCheckpointTests: XCTestCase {
  func testCheckpointSurvivesJournalReopenWithoutSecrets() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "journal-\(UUID().uuidString)")
    let journal = try LocalArchiveJournal.open(at: url)
    var entry = try journal.discover(fingerprint: fingerprint)
    entry = try journal.advance(entryID: entry.id, to: .archived)
    entry = try journal.advance(entryID: entry.id, to: .hashed)
    entry = try journal.advance(entryID: entry.id, to: .queued)
    _ = try journal.checkpoint(
      entryID: entry.id,
      upload: UploadCheckpoint(resumptionToken: "rst_fixture", chunkSizeBytes: 65536, acknowledgedIndices: [0, 1], attemptCount: 2)
    )

    let reopened = try LocalArchiveJournal.open(at: url)
    XCTAssertEqual(reopened.entries.single?.uploadCheckpoint?.acknowledgedIndices, [0, 1])
    XCTAssertFalse(try String(contentsOf: url).contains("credential"))
  }

  private let fingerprint = ArchiveFingerprint(sha256Hex: String(repeating: "a", count: 64), byteSize: 130_000)
}

private extension Array { var single: Element? {
  count == 1 ? first : nil
} }
