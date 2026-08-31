import AgentCore
import Foundation
import XCTest

final class BackendImportPollingTests: XCTestCase {
  func testUnavailablePollRetainsLastKnownObservationAcrossJournalReopen() async throws {
    let journalURL = temporaryDirectory().appendingPathComponent("journal.ndjson")
    let journal = try LocalArchiveJournal.open(at: journalURL)
    let entry = try makeUploadedEntry(in: journal)
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    _ = try journal.bindBackendOperation(entryID: entry.id, operationID: operationID)
    let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
    _ = try journal.recordBackendObservation(
      entryID: entry.id, operationID: operationID, presentation: .processing, observedAt: observedAt
    )

    let coordinator = BackendImportPollCoordinator(journal: journal, polling: UnavailablePoller())
    let retained = await coordinator.refresh(entryID: entry.id, observedAt: observedAt.addingTimeInterval(30))

    XCTAssertEqual(retained?.backendImport?.presentation, .processing)
    XCTAssertEqual(retained?.backendImport?.observedAt, observedAt)
    let reopened = try LocalArchiveJournal.open(at: journalURL)
    XCTAssertEqual(reopened.entries.first?.backendImport?.presentation, .processing)
    XCTAssertEqual(reopened.entries.first?.backendImport?.observedAt, observedAt)
  }

  func testTerminalObservationDoesNotRegressWhenAnUnorderedReadOmitsTimestamp() async throws {
    let journal = try LocalArchiveJournal.open(
      at: temporaryDirectory().appendingPathComponent("journal.ndjson")
    )
    let entry = try makeUploadedEntry(in: journal)
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    _ = try journal.bindBackendOperation(entryID: entry.id, operationID: operationID)
    let poller = OrderedPoller(responses: [completeOperation, runningOperationWithoutTimestamp])
    let coordinator = BackendImportPollCoordinator(journal: journal, polling: poller)

    let terminal = await coordinator.refresh(entryID: entry.id, observedAt: Date(timeIntervalSince1970: 2))
    let retained = await coordinator.refresh(entryID: entry.id, observedAt: Date(timeIntervalSince1970: 3))

    XCTAssertEqual(terminal?.backendImport?.presentation, .importedComplete)
    XCTAssertEqual(retained?.backendImport?.presentation, .importedComplete)
    XCTAssertEqual(retained?.backendImport?.observedAt, Date(timeIntervalSince1970: 2))
  }

  func testTerminalObservationRetainsItsOrderingTimestampWhenARepeatOmitsIt() async throws {
    let journal = try LocalArchiveJournal.open(
      at: temporaryDirectory().appendingPathComponent("journal.ndjson")
    )
    let entry = try makeUploadedEntry(in: journal)
    let operationID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    _ = try journal.bindBackendOperation(entryID: entry.id, operationID: operationID)
    let poller = OrderedPoller(responses: [completeOperation, completeOperationWithoutTimestamp])
    let coordinator = BackendImportPollCoordinator(journal: journal, polling: poller)

    let terminal = await coordinator.refresh(entryID: entry.id, observedAt: Date(timeIntervalSince1970: 4))
    let retained = await coordinator.refresh(entryID: entry.id, observedAt: Date(timeIntervalSince1970: 5))

    XCTAssertEqual(retained?.backendImport?.presentation, .importedComplete)
    XCTAssertEqual(retained?.backendImport?.observedAt, terminal?.backendImport?.observedAt)
    XCTAssertEqual(retained?.backendImport?.backendUpdatedAt, terminal?.backendImport?.backendUpdatedAt)
  }

  private func makeUploadedEntry(in journal: LocalArchiveJournal) throws -> JournalEntry {
    let fingerprint = ArchiveFingerprint(sha256Hex: String(repeating: "a", count: 64), byteSize: 1)
    let discovered = try journal.discover(fingerprint: fingerprint, routing: fixtureRouting())
    let archived = try journal.advance(entryID: discovered.id, to: .archived)
    let hashed = try journal.advance(entryID: archived.id, to: .hashed)
    let queued = try journal.advance(entryID: hashed.id, to: .queued)
    let uploading = try journal.advance(entryID: queued.id, to: .uploading)
    return try journal.advance(entryID: uploading.id, to: .uploaded)
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}

private let completeOperation = Data("""
{
  "status":"succeeded",
  "status_changed_at":"2026-08-27T10:00:15Z",
  "results":[{
    "result_kind":"ai_archive.import",
    "target":"ai_archive:00000000-0000-0000-0000-000000000101",
    "ai_archive_import_summary":{
      "ai_archive_id":"00000000-0000-0000-0000-000000000101",
      "provider":"chatgpt",
      "completeness":"complete",
      "conversation_count":1,
      "message_count":1,
      "asset_count":0,
      "gap_count":0,
      "warning_count":0
    }
  }]
}
""".utf8)

private let runningOperationWithoutTimestamp = Data("""
{"status":"running","results":[]}
""".utf8)

private let completeOperationWithoutTimestamp = Data("""
{
  "status":"succeeded",
  "results":[{
    "result_kind":"ai_archive.import",
    "target":"ai_archive:00000000-0000-0000-0000-000000000101",
    "ai_archive_import_summary":{
      "ai_archive_id":"00000000-0000-0000-0000-000000000101",
      "provider":"chatgpt",
      "completeness":"complete",
      "conversation_count":1,
      "message_count":1,
      "asset_count":0,
      "gap_count":0,
      "warning_count":0
    }
  }]
}
""".utf8)

private actor OrderedPoller: BackendOperationPolling {
  private var responses: [Data]

  init(responses: [Data]) {
    self.responses = responses
  }

  func fetchOperation(_: UUID) async throws -> Data {
    guard !responses.isEmpty else { throw PlatformDeviceTransportError.unavailable }
    return responses.removeFirst()
  }
}

private struct UnavailablePoller: BackendOperationPolling {
  func fetchOperation(_: UUID) async throws -> Data {
    throw PlatformDeviceTransportError.unavailable
  }
}
