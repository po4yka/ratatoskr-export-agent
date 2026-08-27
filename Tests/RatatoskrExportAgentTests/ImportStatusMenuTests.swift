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

  private func entry(presentation: BackendImportPresentation, id: String) -> JournalEntry {
    let entryID = UUID(uuidString: id)!
    return JournalEntry(
      id: entryID,
      fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "c", count: 64), byteSize: 1),
      idempotencyKey: "ratatoskr-export-agent/sha256/\(String(repeating: "c", count: 64))",
      state: .uploaded,
      backendImport: BackendImportObservation(
        operationID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
        presentation: presentation, observedAt: Date(timeIntervalSince1970: 1_700_000_000)
      )
    )
  }
}
