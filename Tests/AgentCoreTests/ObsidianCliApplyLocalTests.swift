import AgentCore
import XCTest

/// What the `cli` channel does with the local file: errors, a base
/// mismatch and an update.
final class ObsidianCliApplyLocalTests: ObsidianCliTestCase {
  func testALocalErrorFailsTheOperationAndThePassGoesOn() async throws {
    try FileManager.default.createDirectory(at: vault.appendingPathComponent("Folder.md"), withIntermediateDirectories: true)
    try write("alpha", to: "A.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue([
      operation(kind: "update", path: "Folder.md", target: nil, base: sha("alpha"), content: sha("beta")),
      operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta")),
    ])
    server.script("/content", status: 200, body: "beta")

    let pass = try? await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(2), "a local error does not end the pass")
    XCTAssertEqual(
      results(server), [["outcome": "failed", "code": "notes.channel.refused"], ["outcome": "applied", "sha256": sha("beta")]]
    )
    XCTAssertEqual(read("A.md"), "beta")
  }

  func testBaseMismatchChangesNothingAndSendsTheLocalFile() async throws {
    try write("local", to: "A.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta")))
    server.script("/content", status: 200, body: "beta")
    let sent = SentChanges()

    let pass = try await client(server).applyQueuedOperations(apply) { sent.add($0) }

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(result(server), ["outcome": "base_mismatch", "local_sha256": sha("local")])
    XCTAssertEqual(read("A.md"), "local", "the local file does not change")
    XCTAssertEqual(try invocations(), [["version"]])
    XCTAssertFalse(server.routes.contains { $0.hasSuffix("/content") }, "no content is read on a mismatch")
    XCTAssertEqual(sent.changes, [VaultChange(sequence: 0, kind: .updated, path: "A.md")], "the local file goes to the change buffer")
  }

  func testUpdateWritesTheBytesAtomicallyAfterABaseMatch() async throws {
    try write("alpha", to: "A.md")
    let before = try inode(of: "A.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta")))
    server.script("/content", status: 200, body: "beta")

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("beta")])
    XCTAssertEqual(read("A.md"), "beta")
    XCTAssertNotEqual(try inode(of: "A.md"), before, "a rename of a new file, not a write into the old one")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path), ["A.md"], "no temporary file is left")
    XCTAssertEqual(try invocations(), [["version"]], "an update needs no CLI command")
  }

  func testAnEmptyFileOfAnUnfinishedCreateIsFinished() async throws {
    try write("", to: "New/Note.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(operation(kind: "create", path: "New/Note.md", target: nil, base: nil, content: sha("body")))
    server.script("/content", status: 200, body: "body")

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("body")], "the empty file is the create of an earlier pass")
    XCTAssertEqual(read("New/Note.md"), "body")
    XCTAssertEqual(try invocations(), [["version"]], "the file exists, so obsidian create does not run again")
  }

  func testContentLongerThanItsLengthIsRefused() async throws {
    try write("alpha", to: "A.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(sized(operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta")), 3))
    server.script("/content", status: 200, body: "beta")

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(result(server), ["outcome": "failed", "code": "notes.channel.refused"])
    XCTAssertEqual(read("A.md"), "alpha")
    let contentRead = server.log.first { $0.path.hasSuffix("/content") }
    XCTAssertEqual(contentRead?.maximumBodyBytes, 3, "the read is bounded by length_bytes")
  }

  private func inode(of path: String) throws -> Int? {
    try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent(path).path)[.systemFileNumber] as? Int
  }
}

/// The changes that the pass gives to the change buffer.
private final class SentChanges: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [VaultChange] = []

  var changes: [VaultChange] { lock.withLock { stored } }

  func add(_ changes: [VaultChange]) {
    lock.withLock { stored += changes }
  }
}
