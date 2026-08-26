import AgentCore
import Foundation
import XCTest

final class JournalCompactionTests: XCTestCase {
  func testCompactionReplaysTheSameProjectionWithinConfiguredBound() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("compact-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("state.journal")
    let limit = 2_048
    let journal = try LocalArchiveJournal.open(at: url, maximumBytes: limit)
    var entry = try journal.discover(fingerprint: compactionFingerprint)
    for state in [.archived, .hashed, .queued, .uploading, .uploaded, .confirmed] as [JournalState] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }

    let reopened = try LocalArchiveJournal.open(at: url, maximumBytes: limit)
    let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
    XCTAssertEqual(reopened.entries, [entry])
    XCTAssertLessThanOrEqual(size?.intValue ?? .max, limit)
  }
}

private let compactionFingerprint = ArchiveFingerprint(
  sha256Hex: "1111111111111111111111111111111111111111111111111111111111111111",
  byteSize: 23
)
