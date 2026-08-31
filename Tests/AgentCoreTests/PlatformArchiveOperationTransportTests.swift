import AgentCore
import Foundation
import XCTest

final class PlatformArchiveOperationTransportTests: XCTestCase {
  func testPrepareBindsReturnedOperationBeforeContentTransfer() async throws {
    let archiveURL = try write(Data("archive".utf8))
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "operation-upload-\(UUID())")
    )
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(Data("archive".utf8)), byteSize: 7)
    var entry = try journal.discover(fingerprint: fingerprint, routing: fixtureRouting(), managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
    let transport = BindingAwareTransport(journal: journal, entryID: entry.id, operationID: operationID)

    try await OperationBoundArchiveSubmitter(journal: journal, transport: transport).submit(
      entryID: entry.id, provider: .chatgpt
    )

    XCTAssertEqual(journal.entries.first?.operationID, operationID)
    XCTAssertEqual(transport.events, ["prepare", "transfer"])
  }
  func testMalformedPrepareResponseDoesNotBindAnOperation() async throws {
    let archiveURL = try write(Data("archive".utf8))
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "malformed-operation-\(UUID())")
    )
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(Data("archive".utf8)), byteSize: 7)
    var entry = try journal.discover(fingerprint: fingerprint, routing: fixtureRouting(), managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let entryID = entry.id

    await XCTAssertThrowsErrorAsync {
      try await OperationBoundArchiveSubmitter(journal: journal, transport: MalformedPrepareTransport()).submit(
        entryID: entryID, provider: .claude
      )
    }

    XCTAssertNil(journal.entries.first(where: { $0.id == entryID })?.backendImport)
  }

  func testInsecurePlatformOriginDoesNotBindAnOperation() async throws {
    let archiveURL = try write(Data("archive".utf8))
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "insecure-operation-\(UUID())")
    )
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(Data("archive".utf8)), byteSize: 7)
    var entry = try journal.discover(fingerprint: fingerprint, routing: fixtureRouting(), managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let entryID = entry.id

    await XCTAssertThrowsErrorAsync {
      try await OperationBoundArchiveSubmitter(
        journal: journal,
        transport: PlatformArchiveHTTPTransport(
          origin: URL(string: "http://ratatoskr.example")!,
          authorizer: OperationFixtureAuthorizer()
        )
      ).submit(entryID: entryID, provider: .chatgpt)
    }

    XCTAssertNil(journal.entries.first(where: { $0.id == entryID })?.backendImport)
  }

  func testBoundOperationIsNotPreparedAgainBeforePolling() async throws {
    let archiveURL = try write(Data("archive".utf8))
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "bound-operation-\(UUID())")
    )
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(Data("archive".utf8)), byteSize: 7)
    var entry = try journal.discover(fingerprint: fingerprint, routing: fixtureRouting(), managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    _ = try journal.bindBackendOperation(
      entryID: entry.id,
      operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000114")!
    )
    let entryID = entry.id
    let transport = CountingPrepareTransport()

    await XCTAssertThrowsErrorAsync {
      try await OperationBoundArchiveSubmitter(journal: journal, transport: transport).submit(
        entryID: entryID, provider: .claude
      )
    }

    XCTAssertEqual(transport.prepareCount, 0)
  }

}
