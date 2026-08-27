import AppKit
import XCTest

@testable import RatatoskrExportAgent

@MainActor
final class ManualUpdateMenuTests: XCTestCase {
  private let updateTitle = "Check for Updates…"

  func testMenuIncludesCheckForUpdatesAction() throws {
    let coordinator = makeCoordinator()
    let menu = AgentMenu.make(coordinator: coordinator)

    let item = try XCTUnwrap(menu.items.first { $0.title == updateTitle })

    XCTAssertNotNil(item.action)
    XCTAssertTrue(item.target === coordinator)
  }

  func testCheckForUpdatesOpensReleasePageOnce() throws {
    var openedURLs: [URL] = []
    let coordinator = AgentMenuCoordinator(
      openUpdateURL: {
        openedURLs.append($0)
        return true
      },
      presentUpdateFailure: {}
    )
    let item = try updateItem(coordinator: coordinator)

    XCTAssertTrue(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
    XCTAssertEqual(
      openedURLs,
      [URL(string: "https://github.com/po4yka/ratatoskr-export-agent/releases/latest")!]
    )
  }

  func testCheckForUpdatesFailureShowsGenericAlert() throws {
    var failureCount = 0
    let coordinator = AgentMenuCoordinator(
      openUpdateURL: { _ in false },
      presentUpdateFailure: { failureCount += 1 }
    )
    let item = try updateItem(coordinator: coordinator)

    XCTAssertTrue(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
    XCTAssertEqual(failureCount, 1)
  }

  private func makeCoordinator() -> AgentMenuCoordinator {
    AgentMenuCoordinator(openUpdateURL: { _ in true }, presentUpdateFailure: {})
  }

  private func updateItem(coordinator: AgentMenuCoordinator) throws -> NSMenuItem {
    let menu = AgentMenu.make(coordinator: coordinator)
    return try XCTUnwrap(menu.items.first { $0.title == updateTitle })
  }
}
