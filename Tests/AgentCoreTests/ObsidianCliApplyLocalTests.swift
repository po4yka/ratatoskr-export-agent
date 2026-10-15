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
}
