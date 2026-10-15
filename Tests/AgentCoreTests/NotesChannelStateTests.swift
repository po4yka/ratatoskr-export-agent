import AgentCore
import XCTest

final class NotesChannelStateTests: NotesChannelTestCase {
  private let first = "00000000-0000-7000-8000-000000000001"

  private var stateFile: URL {
    vault.appendingPathComponent(".state/vault-channels.json")
  }

  func testRestartResumesTheSavedConnectionWithTheManifestFirst() async throws {
    let server = FakeNotesServer()
    let before = client(server, store: FileVaultChannelStateStore(fileURL: stateFile))
    try await before.start()
    try await before.send((1...2).map { VaultChange(sequence: UInt64($0), kind: .deleted, path: "\($0).md") })
    let count = server.log.count

    let after = client(server, store: FileVaultChannelStateStore(fileURL: stateFile))
    try await after.start()
    try await after.send([VaultChange(sequence: 1, kind: .deleted, path: "3.md")])

    XCTAssertEqual(
      Array(server.routes.dropFirst(count)),
      ["POST v1/notes/connections/{id}/manifest", "POST v1/notes/connections/{id}/changes"]
    )
    XCTAssertTrue(server.log.dropFirst(count).allSatisfy { $0.path.contains(first) }, "the restart uses the saved connection")
    XCTAssertEqual(server.batches.last, [3])
    let status = await after.status
    XCTAssertEqual(status, .connected(connectionID: first))
  }

  func testSavedConnectionThatIsGoneConnectsAgainAndSavesTheNewOne() async throws {
    let server = FakeNotesServer()
    let store = FileVaultChannelStateStore(fileURL: stateFile)
    try await store.save(
      VaultChannelState(vaultKey: "vault-key-1", connectionID: "00000000-0000-7000-8000-000000000009", committedSequence: 4)
    )
    server.script("/manifest", status: 404, body: #"{"code":"notes.connection.not_found","message":"m","retryable":false}"#)

    try await client(server, store: store).start()

    XCTAssertEqual(Array(server.routes.prefix(3)), [
      "POST v1/notes/connections/{id}/manifest", "POST v1/notes/connections", "POST v1/notes/connections/{id}/manifest",
    ])
    XCTAssertTrue(server.log.first?.path.contains("000000000009") ?? false, "the manifest goes to the saved connection first")
    let saved = try await store.load(vaultKey: "vault-key-1")
    XCTAssertEqual(saved, VaultChannelState(vaultKey: "vault-key-1", connectionID: first, committedSequence: 0))
  }

  func testStateFileHoldsTheVaultKeyTheConnectionAndTheCommittedSequenceOnly() async throws {
    let server = FakeNotesServer()
    let client = client(server, store: FileVaultChannelStateStore(fileURL: stateFile))
    try await client.start()
    try await client.send((1...2).map { VaultChange(sequence: UInt64($0), kind: .deleted, path: "\($0).md") })

    XCTAssertEqual(
      try? String(contentsOf: stateFile, encoding: .utf8),
      #"{"vaults":[{"committed_sequence":2,"connection_id":"\#(first)","vault_key":"vault-key-1"}]}"#
    )
  }
}
