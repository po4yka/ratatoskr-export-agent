import AgentCore
import XCTest

/// The `cli` channel applies the queue of its connection through a fake
/// `obsidian` executable that records its arguments. The real CLI, the
/// Obsidian app and the owner's vaults are never used.
final class ObsidianCliApplyTests: ObsidianCliTestCase {
  func testRenameUsesObsidianRename() async throws {
    try write("alpha", to: "Projects/Alpha.md")
    let apply = try fakeObsidian(running: true, cases: "rename) mv '\(vault.path)/Projects/Alpha.md' '\(vault.path)/Projects/Apollo.md' ;;")
    let server = queue(operation(kind: "rename", path: "Projects/Alpha.md", target: "Projects/Apollo.md", base: sha("alpha")))

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(
      try invocations().filter { $0.contains("rename") },
      [["vault=Fixture", "rename", "path=Projects/Alpha.md", "name=Apollo"]]
    )
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("alpha")])
  }

  func testDeleteNeverPermanent() async throws {
    try write("old", to: "Notes/Old.md")
    let apply = try fakeObsidian(
      running: true, cases: "delete) mkdir -p '\(vault.path)/.trash' && mv '\(vault.path)/Notes/Old.md' '\(vault.path)/.trash/Old.md' ;;"
    )
    let server = queue(operation(kind: "delete", path: "Notes/Old.md", target: nil, base: sha("old")))

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    let recorded = try invocations()
    XCTAssertFalse(recorded.joined().contains("permanent"), "a delete goes to the trash of Obsidian")
    XCTAssertEqual(recorded.filter { $0.contains("delete") }, [["vault=Fixture", "delete", "path=Notes/Old.md"]])
    XCTAssertEqual(result(server), ["outcome": "applied"])
  }

  func testClosedObsidianLeavesQueue() async throws {
    try write("alpha", to: "A.md")
    let apply = try fakeObsidian(running: false, cases: "")
    let server = queue(operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta")))
    server.script("/content", status: 200, body: "beta")

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .awaitingObsidian)
    XCTAssertEqual(try invocations(), [], "the CLI starts Obsidian, so it is not run")
    XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("A.md"), encoding: .utf8), "alpha")
    XCTAssertEqual(server.routes.filter { $0.hasSuffix("/result") || $0.hasSuffix("/content") }, [])
  }
}
