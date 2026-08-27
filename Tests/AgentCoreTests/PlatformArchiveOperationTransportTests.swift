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
    var entry = try journal.discover(fingerprint: fingerprint, managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
    let transport = BindingAwareTransport(journal: journal, entryID: entry.id, operationID: operationID)

    try await OperationBoundArchiveSubmitter(journal: journal, transport: transport).submit(
      entryID: entry.id, provider: .chatgpt
    )

    XCTAssertEqual(journal.entries.first?.backendImport?.operationID, operationID)
    XCTAssertEqual(transport.events, ["prepare", "transfer"])
  }
  func testMalformedPrepareResponseDoesNotBindAnOperation() async throws {
    let archiveURL = try write(Data("archive".utf8))
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "malformed-operation-\(UUID())")
    )
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(Data("archive".utf8)), byteSize: 7)
    var entry = try journal.discover(fingerprint: fingerprint, managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }

    await XCTAssertThrowsErrorAsync {
      try await OperationBoundArchiveSubmitter(journal: journal, transport: MalformedPrepareTransport()).submit(
        entryID: entry.id, provider: .claude
      )
    }

    XCTAssertNil(journal.entries.first(where: { $0.id == entry.id })?.backendImport)
  }

  func testInsecurePlatformOriginDoesNotBindAnOperation() async throws {
    let archiveURL = try write(Data("archive".utf8))
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "insecure-operation-\(UUID())")
    )
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(Data("archive".utf8)), byteSize: 7)
    var entry = try journal.discover(fingerprint: fingerprint, managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }

    await XCTAssertThrowsErrorAsync {
      try await OperationBoundArchiveSubmitter(
        journal: journal,
        transport: PlatformArchiveHTTPTransport(
          origin: URL(string: "http://ratatoskr.example")!, accessCredential: "fixture"
        )
      ).submit(entryID: entry.id, provider: .chatgpt)
    }

    XCTAssertNil(journal.entries.first(where: { $0.id == entry.id })?.backendImport)
  }

  func testBoundOperationIsNotPreparedAgainBeforePolling() async throws {
    let archiveURL = try write(Data("archive".utf8))
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "bound-operation-\(UUID())")
    )
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(Data("archive".utf8)), byteSize: 7)
    var entry = try journal.discover(fingerprint: fingerprint, managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    _ = try journal.bindBackendOperation(
      entryID: entry.id,
      operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000114")!
    )
    let transport = CountingPrepareTransport()

    await XCTAssertThrowsErrorAsync {
      try await OperationBoundArchiveSubmitter(journal: journal, transport: transport).submit(
        entryID: entry.id, provider: .claude
      )
    }

    XCTAssertEqual(transport.prepareCount, 0)
  }

}

private struct MalformedPrepareTransport: PlatformArchiveOperationTransport {
  func prepare(
    provider _: PlatformArchiveProvider,
    fingerprint _: ArchiveFingerprint,
    idempotencyKey _: String
  ) async throws -> PlatformArchivePrepared {
    throw PlatformDeviceTransportError.invalidResponse
  }

  func transfer(
    provider _: PlatformArchiveProvider,
    prepared _: PlatformArchivePrepared,
    archiveURL _: URL,
    fingerprint _: ArchiveFingerprint
  ) async throws {}
}

private final class CountingPrepareTransport: @unchecked Sendable, PlatformArchiveOperationTransport {
  private(set) var prepareCount = 0

  func prepare(
    provider _: PlatformArchiveProvider,
    fingerprint _: ArchiveFingerprint,
    idempotencyKey _: String
  ) async throws -> PlatformArchivePrepared {
    prepareCount += 1
    return PlatformArchivePrepared(
      operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000115")!,
      uploadPath: "/v1/ai-archives/claude/00000000-0000-0000-0000-000000000115/content"
    )
  }

  func transfer(
    provider _: PlatformArchiveProvider,
    prepared _: PlatformArchivePrepared,
    archiveURL _: URL,
    fingerprint _: ArchiveFingerprint
  ) async throws {}
}

private func XCTAssertThrowsErrorAsync(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("expected an error", file: file, line: line)
  } catch {}
}

final class BindingAwareTransport: @unchecked Sendable, PlatformArchiveOperationTransport {
  let journal: LocalArchiveJournal
  let entryID: UUID
  let operationID: UUID
  var events = [String]()

  init(journal: LocalArchiveJournal, entryID: UUID, operationID: UUID) {
    self.journal = journal
    self.entryID = entryID
    self.operationID = operationID
  }

  func prepare(
    provider _: PlatformArchiveProvider,
    fingerprint _: ArchiveFingerprint,
    idempotencyKey _: String
  ) async throws -> PlatformArchivePrepared {
    events.append("prepare")
    return PlatformArchivePrepared(
      operationID: operationID,
      uploadPath: "/v1/ai-archives/chatgpt/\(operationID.uuidString.lowercased())/content"
    )
  }

  func transfer(
    provider _: PlatformArchiveProvider,
    prepared _: PlatformArchivePrepared,
    archiveURL _: URL,
    fingerprint _: ArchiveFingerprint
  ) async throws {
    events.append("transfer")
    XCTAssertEqual(journal.entries.first(where: { $0.id == entryID })?.backendImport?.operationID, operationID)
  }

}
