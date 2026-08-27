import AgentCore
import Foundation
import XCTest

final class UploadRetryJournalTests: XCTestCase {
  func testRetryableFailureReturnsUploadingEntryToQueuedWithLaterEligibility() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "retry-\(UUID().uuidString)")
    let journal = try LocalArchiveJournal.open(at: url)
    var entry = try journal.discover(fingerprint: fingerprint)
    for state in [JournalState.archived, .hashed, .queued, .uploading] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let retryAt = Date(timeIntervalSince1970: 2000)
    let deferred = try journal.deferRetry(
      entryID: entry.id,
      upload: UploadCheckpoint(
        resumptionToken: "rst",
        chunkSizeBytes: 65536,
        attemptCount: 1,
        nextRetryAt: retryAt
      )
    )
    XCTAssertEqual(deferred.state, .queued)
    XCTAssertEqual(try LocalArchiveJournal.open(at: url).entries.single?.uploadCheckpoint?.nextRetryAt, retryAt)
  }

  private let fingerprint = ArchiveFingerprint(sha256Hex: String(repeating: "b", count: 64), byteSize: 1)
}

private extension Array { var single: Element? {
  count == 1 ? first : nil
} }
