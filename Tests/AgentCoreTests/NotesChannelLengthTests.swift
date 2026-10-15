import AgentCore
import XCTest

final class NotesChannelLengthTests: NotesChannelTestCase {
  func testChangeWithoutLengthGetsItFromTheFile() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    try Data("beta".utf8).write(to: vault.appendingPathComponent("B.md"))
    let digest = try StreamingHasher().fingerprint(at: vault.appendingPathComponent("B.md")).sha256Hex

    try? await client.send([VaultChange(sequence: 1, kind: .created, path: "B.md", sha256: digest)])

    let sent = server.log.last { $0.path.hasSuffix("/changes") }?.body ?? Data()
    let batch = try? JSONDecoder().decode(VaultChangeBatch.self, from: sent)
    XCTAssertEqual(batch?.changes.first?.byteLength, 4)
    XCTAssertEqual(server.committed, 1)
  }

  func testChangeWithoutLengthWhoseFileIsGoneSendsAManifest() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    let count = server.log.count

    try? await client.send([VaultChange(sequence: 1, kind: .updated, path: "Gone.md", sha256: String(repeating: "a", count: 64))])

    XCTAssertEqual(Array(server.routes.dropFirst(count)), ["POST v1/notes/connections/{id}/manifest"])
    let status = await client.status
    XCTAssertEqual(status, .connected(connectionID: "00000000-0000-7000-8000-000000000001"))
  }
}
