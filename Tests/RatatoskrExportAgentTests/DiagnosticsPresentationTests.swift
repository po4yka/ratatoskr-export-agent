import AgentCore
import XCTest

@testable import RatatoskrExportAgent

@MainActor
final class DiagnosticsPresentationTests: XCTestCase {
  func testStatusMenuOpensDiagnostics() {
    let menu = AgentMenu.make(coordinator: AgentMenuCoordinator())
    let item = menu.items.first { $0.title == AgentMenu.diagnosticsTitle }

    XCTAssertNotNil(item)
    XCTAssertEqual(item?.action, #selector(AgentMenuCoordinator.diagnosticsSelected))
  }

  func testDiagnosticsRowsExposeEveryRequiredCategoryWithoutCoordinates() {
    let snapshot = OperationalDiagnosticsSnapshot(
      folderPermissions: .init(accessible: 1, needsReauthorization: 1, missing: 0, denied: 0),
      notifications: .deniedOrUnavailable,
      diskSpace: .available(bytes: 4_194_304),
      journal: .healthy(entryCount: 2),
      queue: .available(.init(active: 0, queued: 2, paused: 0, retrying: 0, failed: 0)),
      updateCheck: .manualDownload(currentVersion: "1.2.3")
    )
    let viewModel = DiagnosticsViewModel(snapshot: snapshot)

    XCTAssertEqual(
      viewModel.rows.map(\.title),
      ["Folder access", "Notifications", "Disk space", "Journal", "Queue", "Updates"]
    )
    let rendered = viewModel.rows.map { "\($0.title):\($0.value)" }.joined(separator: "\n")
    XCTAssertFalse(rendered.contains("/Users/private"))
    XCTAssertFalse(rendered.contains("https://archive.internal"))
    XCTAssertTrue(rendered.contains("Manual download; current version 1.2.3"))
  }
}
