import AgentCore
import XCTest

final class NotesChannelBatchTests: NotesChannelTestCase {
  func testSequenceGapSendsAgainFromTheCommittedSequence() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    try await client.send((1...3).map { VaultChange(sequence: UInt64($0), kind: .deleted, path: "\($0).md") })
    server.committed = 1

    try await client.send([VaultChange(sequence: 4, kind: .deleted, path: "4.md")])

    XCTAssertEqual(server.batches, [[1, 2, 3], [4], [2]])
    XCTAssertEqual(server.committed, 2)
  }

  func testBytesMissingUploadsThoseHashesAndSendsTheBatchAgain() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()
    try Data("beta".utf8).write(to: vault.appendingPathComponent("B.md"))
    let before = server.log.count

    try await client.send([
      VaultChange(sequence: 1, kind: .created, path: "B.md", sha256: try fingerprint("B.md"), byteLength: 4),
      VaultChange(sequence: 2, kind: .created, path: "Blank.md", sha256: empty, byteLength: 0),
    ])

    XCTAssertEqual(
      Array(server.routes.dropFirst(before)),
      [
        "POST v1/notes/connections/{id}/changes",
        "POST v1/notes/connections/{id}/blobs",
        "GET v1/notes/connections/{id}/blobs/nst_2/status",
        "PUT v1/notes/connections/{id}/blobs/nst_2/chunks/0",
        "POST v1/notes/connections/{id}/blobs/nst_2/finalize",
        "POST v1/notes/connections/{id}/changes",
      ]
    )
    XCTAssertEqual(server.batches, [[1, 2], [1, 2]])
  }

  func testBatchTooLargeSplitsTheBatch() async throws {
    let server = FakeNotesServer()
    server.maximumChanges = 2
    let client = client(server)
    try await client.start()

    try await client.send((1...3).map { VaultChange(sequence: UInt64($0), kind: .deleted, path: "\($0).md") })

    XCTAssertEqual(server.batches, [[1, 2, 3], [1, 2], [3]])
  }

  func testMoreThan256ChangesGoInBatchesOf256() async throws {
    let server = FakeNotesServer()
    let client = client(server)
    try await client.start()

    try await client.send((1...257).map { VaultChange(sequence: UInt64($0), kind: .deleted, path: "\($0).md") })

    XCTAssertEqual(server.batches.map(\.count), [256, 1])
    XCTAssertEqual(server.committed, 257)
  }

  private func fingerprint(_ path: String) throws -> String {
    try StreamingHasher().fingerprint(at: vault.appendingPathComponent(path)).sha256Hex
  }
}
