import AgentCore
import XCTest

final class NotesChannelClientTests: NotesChannelTestCase {
  func testConnectSendsTheManifestAndUploadsWhatItNeedsIn1MiBChunks() async throws {
    let server = FakeNotesServer()

    try await client(server).start()

    XCTAssertEqual(
      server.routes,
      [
        "POST v1/notes/connections",
        "POST v1/notes/connections/{id}/manifest",
        "POST v1/notes/connections/{id}/blobs",
        "GET v1/notes/connections/{id}/blobs/nst_1/status",
        "PUT v1/notes/connections/{id}/blobs/nst_1/chunks/0",
        "PUT v1/notes/connections/{id}/blobs/nst_1/chunks/1",
        "POST v1/notes/connections/{id}/blobs/nst_1/finalize",
        "POST v1/notes/connections/{id}/manifest",
      ]
    )
    let connect = try XCTUnwrap(server.log.first?.body)
    XCTAssertEqual(
      try JSONSerialization.jsonObject(with: connect) as? [String: String],
      ["channel": "cli", "vault_key": "vault-key-1", "vault_display_name": "Fixture"]
    )
    let open = try JSONDecoder().decode(BlobUploadDeclaration.self, from: server.log[2].body ?? Data())
    XCTAssertEqual(open.chunkSizeBytes, 1_048_576)
    XCTAssertEqual(open.declaredSizeBytes, 1_572_864)
    XCTAssertEqual(server.log[4].body?.count, 1_048_576)
  }

  func testChangesAfterTheManifestContinueTheCommittedSequence() async throws {
    let server = FakeNotesServer()
    server.committed = 7
    let client = client(server)
    try await client.start()

    try await client.send([
      VaultChange(sequence: 1, kind: .created, path: "New.md", sha256: empty, byteLength: 0),
      VaultChange(sequence: 2, kind: .deleted, path: "Old.md"),
    ])

    XCTAssertEqual(server.batches, [[8, 9]])
    let status = await client.status
    XCTAssertEqual(status, .connected(connectionID: "00000000-0000-7000-8000-000000000001"))
  }

  func testMissingConnectionConnectsAgainAndSendsTheManifest() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    server.script(
      "/changes", status: 404,
      body: #"{"code":"notes.connection.not_found","message":"m","retryable":false}"#
    )
    let before = server.log.count

    try await client.send([VaultChange(sequence: 1, kind: .deleted, path: "Gone.md")])

    XCTAssertEqual(
      Array(server.routes.dropFirst(before)),
      ["POST v1/notes/connections/{id}/changes", "POST v1/notes/connections", "POST v1/notes/connections/{id}/manifest"]
    )
    XCTAssertTrue(server.log.last?.path.contains("000000000002") ?? false, "the manifest goes to the new connection")
    let status = await client.status
    XCTAssertEqual(status, .connected(connectionID: "00000000-0000-7000-8000-000000000002"))
  }

  func testChannelMismatchStopsAndSurfacesTheStatus() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    server.script(
      "/changes", status: 409,
      body: #"{"code":"notes.channel_mismatch","message":"m","retryable":false}"#
    )

    let first = await capturedError { try await client.send([VaultChange(sequence: 1, kind: .deleted, path: "X.md")]); return "" }
    let count = server.log.count
    let second = await capturedError { try await client.send([VaultChange(sequence: 2, kind: .deleted, path: "Y.md")]); return "" }

    XCTAssertEqual(first as? NotesChannelError, .channelMismatch)
    XCTAssertEqual(second as? NotesChannelError, .channelMismatch)
    XCTAssertEqual(server.log.count, count, "a stopped channel sends nothing")
    let status = await client.status
    XCTAssertEqual(status, .stopped(code: "notes.channel_mismatch"))
  }
}
