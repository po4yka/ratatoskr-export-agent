import AgentCore
import XCTest

final class NotesChannelPermanentTests: NotesChannelTestCase {
  private func fault(_ code: String) -> String {
    #"{"code":"\#(code)","message":"m","retryable":false}"#
  }

  func testVaultAlreadyConnectedStopsAndNamesTheCause() async throws {
    let server = FakeNotesServer()
    server.script("v1/notes/connections", status: 409, body: fault("notes.connection.vault_already_connected"))
    let client = client(server)

    let first = await capturedError { try await client.start(); return "" }
    let count = server.log.count
    let second = await capturedError { try await client.send([VaultChange(sequence: 1, kind: .deleted, path: "X.md")]); return "" }

    XCTAssertEqual(first as? NotesChannelError, .permanent(code: "notes.connection.vault_already_connected"))
    XCTAssertEqual(second as? NotesChannelError, .permanent(code: "notes.connection.vault_already_connected"))
    XCTAssertEqual(server.log.count, count, "a stopped channel sends nothing")
    let status = await client.status
    XCTAssertEqual(status, .stopped(code: "notes.connection.vault_already_connected"))
  }

  func testInvalidRequestAndAManifestTooLargeStop() async throws {
    let invalid = FakeNotesServer()
    invalid.script("/manifest", status: 400, body: fault("notes.request.invalid"))
    let large = FakeNotesServer()
    large.script("/manifest", status: 413, body: "")
    let first = client(invalid)
    let second = client(large)

    _ = await capturedError { try await first.start(); return "" }
    _ = await capturedError { try await second.start(); return "" }

    let invalidStatus = await first.status
    let largeStatus = await second.status
    XCTAssertEqual(invalidStatus, .stopped(code: "notes.request.invalid"))
    XCTAssertEqual(largeStatus, .stopped(code: "export_agent.manifest_too_large"))
  }

  func testManifestOverTheEntryLimitIsNotSent() async throws {
    let server = FakeNotesServer()
    let entries = (0...100_000).map { VaultManifestEntry(path: "\($0).md", sha256: empty, lengthBytes: 0) }
    let client = NotesChannelClient(
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture",
      manifest: { var manifest = VaultManifest(index: [:]); manifest.entries = entries; return manifest }
    )

    _ = await capturedError { try await client.start(); return "" }

    XCTAssertEqual(server.routes, ["POST v1/notes/connections"], "notes takes at most 100 000 entries")
    let status = await client.status
    XCTAssertEqual(status, .stopped(code: "export_agent.manifest_too_large"))
  }

  func testStatusTitlesNameTheCause() {
    let rows = ["notes.connection.vault_already_connected", "notes.request.invalid", "export_agent.manifest_too_large"]
      .map { VaultStatusRow(id: UUID(), displayName: "Work", status: .stopped(code: $0)) }

    XCTAssertEqual(
      rows.map(VaultStatusMenuProjection.title),
      [
        "Vault Work: stopped, the vault already has another connection",
        "Vault Work: stopped, notes refused a request of this agent",
        "Vault Work: stopped, the vault has more than 100 000 files",
      ]
    )
    XCTAssertEqual(rows.map(VaultStatusMenuProjection.canConnectAgain), [true, false, false])
  }
}
