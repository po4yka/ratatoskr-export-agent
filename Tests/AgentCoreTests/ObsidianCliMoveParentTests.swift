import AgentCore
import XCTest

/// The real Obsidian CLI does not create the parent of a move destination.
final class ObsidianCliMoveParentTests: ObsidianCliTestCase {
  func testMoveCreatesTheMissingDestinationFolderBeforeTheCLI() async throws {
    try write("x", to: "A/X.md")
    let apply = try fakeObsidian(
      running: true, cases: "move) mv '\(vault.path)/A/X.md' '\(vault.path)/New/Nested/X.md' ;;"
    )
    let server = queue(operation(kind: "move", path: "A/X.md", target: "New/Nested/X.md", base: sha("x")))

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("x")])
    XCTAssertEqual(read("New/Nested/X.md"), "x")
    XCTAssertNil(read("A/X.md"))
    XCTAssertEqual(try invocations(), [["version"], ["vault=Fixture", "move", "path=A/X.md", "to=New/Nested/X.md"]])
  }
}
