import AgentCore
import Foundation
import XCTest

final class UploadQueueControlTests: XCTestCase {
  func testPauseCancelAndExplicitRetryPreserveArchiveIdentity() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "control-\(UUID().uuidString)")
    let journal = try LocalArchiveJournal.open(at: url)
    var entry = try journal.discover(fingerprint: fingerprint)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    _ = try journal.checkpoint(entryID: entry.id, upload: UploadCheckpoint(resumptionToken: "rst", chunkSizeBytes: 65536, nextRetryAt: .distantFuture))
    let paused = try journal.controlRetry(entryID: entry.id, control: .paused)
    XCTAssertEqual(paused.idempotencyKey, entry.idempotencyKey)
    XCTAssertEqual(paused.uploadCheckpoint?.control, .paused)
    let retried = try journal.controlRetry(entryID: entry.id, control: .active, now: Date(timeIntervalSince1970: 1))
    XCTAssertEqual(retried.uploadCheckpoint?.nextRetryAt, Date(timeIntervalSince1970: 1))
    let cancelled = try journal.controlRetry(entryID: entry.id, control: .cancelled)
    XCTAssertEqual(cancelled.uploadCheckpoint?.control, .cancelled)
  }

  private let fingerprint = ArchiveFingerprint(sha256Hex: String(repeating: "c", count: 64), byteSize: 1)
}
