import AgentCore
import Foundation
import XCTest

final class LocalArchiveJournalTests: XCTestCase {
  func testEveryTransitionIsPersistedBeforeReturning() throws {
    let url = journalURL()
    let journal = try makeJournal(at: url)
    var entry = try journal.discover(fingerprint: fixtureFingerprint())
    XCTAssertEqual(entry.state, .discovered)
    let states: [JournalState] = [.archived, .hashed, .queued, .uploading, .uploaded, .confirmed]
    for state in states {
      entry = try journal.advance(entryID: entry.id, to: state)
      XCTAssertEqual(entry.state, state)
    }
    let reopened = try LocalArchiveJournal.open(at: url)
    XCTAssertEqual(reopened.entries, [entry])
  }

  func testIdempotencyKeyIsStableForTheSameDigest() throws {
    let first = try makeJournal(at: journalURL()).discover(fingerprint: fixtureFingerprint())
    let second = try makeJournal(at: journalURL()).discover(fingerprint: fixtureFingerprint())
    XCTAssertEqual(first.idempotencyKey, second.idempotencyKey)
    XCTAssertTrue(first.idempotencyKey.hasSuffix(fixtureFingerprint().sha256Hex))
  }

  func testDuplicateDigestCannotCreateSecondEntry() throws {
    let journal = try makeJournal(at: journalURL())
    _ = try journal.discover(fingerprint: fixtureFingerprint())
    XCTAssertThrowsError(try journal.discover(fingerprint: fixtureFingerprint()))
  }

  private func makeJournal(at url: URL) throws -> LocalArchiveJournal {
    try LocalArchiveJournal.open(at: url)
  }

  private func journalURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("journal-\(UUID().uuidString)", isDirectory: true)
      .appendingPathComponent("state.journal")
  }

  private func fixtureFingerprint() -> ArchiveFingerprint {
    ArchiveFingerprint(
      sha256Hex: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      byteSize: 17
    )
  }
}
