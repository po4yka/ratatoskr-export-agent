import AgentCore
import AppKit
@testable import RatatoskrExportAgent
import XCTest

@MainActor
final class VaultStatusMenuTests: XCTestCase {
  func testVaultRowsShowTheStatusAndARemovedVaultHasConnectAgain() {
    let coordinator = AgentMenuCoordinator()
    let menu = AgentMenu.make(coordinator: coordinator)
    let removed = VaultStatusRow(id: UUID(), displayName: "Notes", status: .stopped(code: "notes.connection.removed"))

    AgentMenu.apply(
      vaultRows: [VaultStatusRow(id: UUID(), displayName: "Work", status: .connected), removed], to: menu
    )
    let items = menu.items.filter { $0.tag == AgentMenu.vaultStatusItemTag }

    XCTAssertEqual(
      items.map(\.title),
      ["Vault Work: connected", "Vault Notes: stopped, the connection was removed", "Connect Vault Notes Again"]
    )
    XCTAssertEqual(items.last?.representedObject as? UUID, removed.id)
    XCTAssertTrue(items.last?.target === coordinator)
    XCTAssertEqual(items.last?.action, #selector(AgentMenuCoordinator.connectVaultAgainSelected(_:)))
  }
}
