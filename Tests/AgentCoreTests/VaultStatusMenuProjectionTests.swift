import AgentCore
import XCTest

final class VaultStatusMenuProjectionTests: XCTestCase {
  func testEachStatusHasATitleAndOnlyARemovedVaultCanConnectAgain() {
    let rows = [
      VaultSyncStatus.connecting, .connected, .retrying,
      .stopped(code: "notes.channel_mismatch"), .stopped(code: "notes.connection.removed"),
    ].map { VaultStatusRow(id: UUID(), displayName: "Work", status: $0) }

    XCTAssertEqual(
      rows.map(VaultStatusMenuProjection.title),
      [
        "Vault Work: connecting",
        "Vault Work: connected",
        "Vault Work: offline, trying again",
        "Vault Work: stopped, another device or channel sends this vault",
        "Vault Work: stopped, the connection was removed",
      ]
    )
    XCTAssertEqual(rows.map(VaultStatusMenuProjection.canConnectAgain), [false, false, false, false, true])
  }

  func testAVaultThatWaitsForObsidianHasItsTitle() {
    let row = VaultStatusRow(id: UUID(), displayName: "Work", status: .awaitingObsidian)

    XCTAssertEqual(VaultStatusMenuProjection.title(row), "Vault Work: waits for Obsidian")
    XCTAssertFalse(VaultStatusMenuProjection.canConnectAgain(row))
  }
}
