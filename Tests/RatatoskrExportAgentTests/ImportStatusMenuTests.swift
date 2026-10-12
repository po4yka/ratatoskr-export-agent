import AgentCore
import AppKit
@testable import RatatoskrExportAgent
import XCTest

@MainActor
final class ImportStatusMenuTests: XCTestCase {
  func testRendersCompleteGapsAndLastKnownUnavailableWithoutPrivateDetails() {
    let complete = entry(presentation: .importedComplete, id: "00000000-0000-0000-0000-000000000001")
    let gaps = entry(presentation: .importedWithGaps(gapCount: 73), id: "00000000-0000-0000-0000-000000000002")
    let menu = AgentMenu.make(coordinator: AgentMenuCoordinator(), importEntries: [complete, gaps])
    let rows = menu.items.filter { $0.tag == AgentMenu.importStatusItemTag }.map(\.title)

    XCTAssertTrue(rows.contains { $0.contains("Imported complete") && $0.contains("last known") })
    XCTAssertTrue(rows.contains { $0.contains("Imported with gaps") && $0.contains("last known") })
    XCTAssertFalse(rows.joined(separator: " ").contains("chatgpt"))
    XCTAssertFalse(rows.first(where: { $0.contains("Imported with gaps") })?.contains("73") ?? true)
  }

  func testShowsWhyAnUploadFailedWithoutPrivateDetails() {
    let exhausted = failedUpload(id: "00000011-0000-0000-0000-000000000011", reason: .retriesExhausted)
    let expired = failedUpload(id: "00000012-0000-0000-0000-000000000012", reason: .sessionExpired)
    let menu = AgentMenu.make(coordinator: AgentMenuCoordinator(), importEntries: [exhausted, expired])
    let rows = menu.items.filter { $0.tag == AgentMenu.importStatusItemTag }.map(\.title)

    XCTAssertEqual(rows, ["00000011: Upload failed (retries exhausted)", "00000012: Upload failed (session expired)"])
    XCTAssertFalse(rows.joined().contains("private-token"))
  }

  private func failedUpload(id: String, reason: UploadCheckpoint.FailureReason) -> JournalEntry {
    JournalEntry(
      id: UUID(uuidString: id)!,
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "c", count: 64), byteSize: 1),
      idempotencyKey: "ratatoskr-export-agent/sha256/\(String(repeating: "c", count: 64))",
      routing: appFixtureRouting(),
      state: .queued,
      uploadCheckpoint: UploadCheckpoint(
        resumptionToken: "private-token", chunkSizeBytes: 1, control: .failed, failureReason: reason
      )
    )
  }

  private func entry(presentation: BackendImportPresentation, id: String) -> JournalEntry {
    let entryID = UUID(uuidString: id)!
    return JournalEntry(
      id: entryID,
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "c", count: 64), byteSize: 1),
      idempotencyKey: "ratatoskr-export-agent/sha256/\(String(repeating: "c", count: 64))",
      routing: appFixtureRouting(),
      state: .uploaded,
      backendImport: BackendImportObservation(
        operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
        presentation: presentation, observedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )
  }
}
