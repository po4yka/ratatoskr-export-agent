import AgentCore
import XCTest

/// Which paths the `cli` channel writes, and how it moves and creates files.
final class ObsidianCliApplyPathTests: ObsidianCliTestCase {
  func testUnsafePathsFailWithUnsafePath() async throws {
    let outside = root.appendingPathComponent("Outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data("secret".utf8).write(to: outside.appendingPathComponent("x.md"))
    try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("Link"), withDestinationURL: outside)
    try FileManager.default.createSymbolicLink(
      at: vault.appendingPathComponent("Leak.md"), withDestinationURL: outside.appendingPathComponent("x.md")
    )
    let paths = ["/etc/x.md", "../x.md", "A//B.md", "./A.md", ".obsidian/app.json", "Link/x.md", "Leak.md"]
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(paths.map { operation(kind: "update", path: $0, target: nil, base: sha("secret"), content: sha("beta")) })
    server.script("/content", status: 200, body: "beta")

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(paths.count))
    XCTAssertEqual(results(server), paths.map { _ in ["outcome": "failed", "code": "notes.write.unsafe_path"] })
    XCTAssertEqual(try String(contentsOf: outside.appendingPathComponent("x.md"), encoding: .utf8), "secret")
    XCTAssertFalse(server.routes.contains { $0.hasSuffix("/content") }, "no content is read for a refused path")
  }

  func testBackslashesControlCharactersColonsAndTrailingDotsFailWithUnsafePath() async throws {
    try write("a", to: "Notes/A.md")
    let paths = [
      "A\\.obsidian\\plugins\\x.md", "..\\x.md", "A\u{0}.md", "A\nB.md", "A\u{7F}.md", "Notes/.. /x.md", "Notes/. /x.md",
      "A:B.md", "Notes./x.md", "Notes /x.md",
    ]
    let targets = ["Notes\\B.md", "Notes/B:C.md"]
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(
      paths.map { operation(kind: "update", path: $0, target: nil, base: nil, content: sha("beta")) }
        + targets.map { operation(kind: "move", path: "Notes/A.md", target: $0, base: sha("a")) }
    )
    for _ in paths {
      server.script("/content", status: 200, body: "beta")
    }

    let pass = try? await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(paths.count + targets.count))
    XCTAssertEqual(results(server), (paths + targets).map { _ in ["outcome": "failed", "code": "notes.write.unsafe_path"] })
    XCTAssertEqual(try invocations(), [["version"]], "no CLI command runs for an unsafe path")
    XCTAssertFalse(server.routes.contains { $0.hasSuffix("/content") }, "no content is read for an unsafe path")
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path), ["Notes"], "nothing is written")
  }

  func testMoveUsesObsidianMoveWithTheTargetPath() async throws {
    try write("x", to: "A/X.md")
    let apply = try fakeObsidian(
      running: true, cases: "move) mkdir -p '\(vault.path)/B' && mv '\(vault.path)/A/X.md' '\(vault.path)/B/X.md' ;;"
    )
    let server = queue(operation(kind: "move", path: "A/X.md", target: "B/X.md", base: sha("x")))

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(try invocations().filter { $0.count > 1 }, [["vault=Fixture", "move", "path=A/X.md", "to=B/X.md"]])
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("x")])
  }

  func testCreateMakesAnEmptyFileWithTheCLIThenWritesTheBytes() async throws {
    let file = "\(vault.path)/New/Note.md"
    let apply = try fakeObsidian(
      running: true,
      cases: "create) test -e '\(file)' && echo existed >> '\(log.path)'; mkdir -p '\(vault.path)/New' && : > '\(file)' ;;"
    )
    let server = queue(operation(kind: "create", path: "New/Note.md", target: nil, base: nil, content: sha("body")))
    server.script("/content", status: 200, body: "body")

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(try invocations(), [["version"], ["vault=Fixture", "create", "path=New/Note.md"]], "the CLI makes the file first")
    XCTAssertEqual(read("New/Note.md"), "body", "the bytes replace the empty file of the CLI")
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("body")])
  }
}
