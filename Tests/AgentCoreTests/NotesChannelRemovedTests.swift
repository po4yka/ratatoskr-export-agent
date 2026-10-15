import AgentCore
import XCTest

final class NotesChannelRemovedTests: NotesChannelTestCase {
  private let removed = #"{"code":"notes.connection.removed","message":"m","retryable":false}"#

  func testRemovedConnectionStopsWithoutConnectingAgain() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    server.script("/changes", status: 410, body: removed)

    let first = await capturedError { try await client.send([VaultChange(sequence: 1, kind: .deleted, path: "X.md")]); return "" }
    let count = server.log.count
    let second = await capturedError { try await client.send([VaultChange(sequence: 2, kind: .deleted, path: "Y.md")]); return "" }
    let again = await capturedError { try await client.start(); return "" }

    XCTAssertEqual(first as? NotesChannelError, .connectionRemoved)
    XCTAssertEqual(second as? NotesChannelError, .connectionRemoved)
    XCTAssertEqual(again as? NotesChannelError, .connectionRemoved)
    XCTAssertEqual(server.log.count, count, "a removed connection sends nothing more")
    XCTAssertFalse(server.routes.dropFirst().contains("POST v1/notes/connections"), "the agent does not connect again")
    let status = await client.status
    XCTAssertEqual(status, .stopped(code: "notes.connection.removed"))
  }

  func testRemovedConnectionOnAnUploadStops() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    try Data("beta".utf8).write(to: vault.appendingPathComponent("B.md"))
    let digest = try StreamingHasher().fingerprint(at: vault.appendingPathComponent("B.md")).sha256Hex
    server.script("/blobs", status: 410, body: removed)

    let error = await capturedError {
      try await client.send([VaultChange(sequence: 1, kind: .created, path: "B.md", sha256: digest, byteLength: 4)])
      return ""
    }

    XCTAssertEqual(error as? NotesChannelError, .connectionRemoved)
    XCTAssertEqual(server.routes.last, "POST v1/notes/connections/{id}/blobs")
    let status = await client.status
    XCTAssertEqual(status, .stopped(code: "notes.connection.removed"))
  }
}
