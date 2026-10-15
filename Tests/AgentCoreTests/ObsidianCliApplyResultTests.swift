import AgentCore
import XCTest

/// How the `cli` channel reports a result: the upload that notes asks for,
/// a pass after a crash, the hash after `property:set`, and the thread of
/// the CLI.
final class ObsidianCliApplyResultTests: ObsidianCliTestCase {
  func testBytesMissingUploadsTheFileAndSendsTheResultAgain() async throws {
    try write("alpha", to: "A.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let missing = #"{"code":"notes.channel.bytes_missing","message":"m","retryable":false,"missing_sha256":["\#(sha("beta"))"]}"#
    let server = queue(
      [operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta"))],
      results: [(409, missing), (200, #"{"operation_id":"\#(operationID)","state":"succeeded"}"#)]
    )
    server.script("/content", status: 200, body: "beta")

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(results(server), [["outcome": "applied", "sha256": sha("beta")], ["outcome": "applied", "sha256": sha("beta")]])
    let routes = server.routes
    let sent = routes.indices.filter { routes[$0].hasSuffix("/result") }
    let finalized = routes.firstIndex { $0.hasSuffix("/finalize") }
    XCTAssertEqual(sent.count, 2)
    XCTAssertNotNil(finalized, "the bytes are uploaded")
    XCTAssertTrue((sent.first ?? 0) < (finalized ?? -1) && (finalized ?? 0) < (sent.last ?? 0), "upload between the two results")
  }

  func testAPassAfterACrashBeforeTheResultReportsApplied() async throws {
    try write("beta", to: "A.md")
    try write("alpha", to: "Projects/Apollo.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue([
      operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta")),
      operation(kind: "rename", path: "Projects/Alpha.md", target: "Projects/Apollo.md", base: sha("alpha")),
      operation(kind: "delete", path: "Notes/Old.md", target: nil, base: sha("old")),
    ])

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(3))
    XCTAssertEqual(
      results(server),
      [["outcome": "applied", "sha256": sha("beta")], ["outcome": "applied", "sha256": sha("alpha")], ["outcome": "applied"]]
    )
    XCTAssertEqual(try invocations(), [["version"]], "nothing is applied again")
    XCTAssertFalse(server.routes.contains { $0.hasSuffix("/content") })
  }

  func testSetPropertyReadsTheHashAgainWhenTheFileDidNotChangeYet() async throws {
    try write("plain", to: "P.md")
    let file = vault.appendingPathComponent("P.md")
    // Obsidian writes the frontmatter after the CLI returned.
    let apply = try fakeObsidian(running: true, cases: "") {
      try? Data("---\nstatus: done\n---\nplain".utf8).write(to: file)
    }
    let server = queue(
      sized(operation(kind: "set_property", path: "P.md", target: nil, base: sha("plain"), content: sha(#""done""#), property: ("status", "set")), 6)
    )
    server.script("/content", status: 200, body: #""done""#)

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(try invocations().last, ["vault=Fixture", "property:set", "name=status", "value=done", "path=P.md"])
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("---\nstatus: done\n---\nplain")])
  }

  func testTheCLIRunsOnItsOwnThread() async throws {
    try write("plain", to: "P.md")
    let runner = ThreadRecordingRunner()
    let apply = ObsidianCLIApply(vault: vault, vaultName: "Fixture", runner: runner, obsidianRunning: { true }, settle: {})
    let server = queue(operation(kind: "set_property", path: "P.md", target: nil, base: sha("plain"), property: ("status", "remove")))

    _ = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(runner.threads, ["obsidian-cli", "obsidian-cli"], "a CLI run of up to 30 s holds no thread of the pool")
  }
}

/// Answers every run with success and records the name of the thread.
private final class ThreadRecordingRunner: ObsidianCLIRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var names: [String] = []

  var threads: [String] { lock.withLock { names } }

  func run(_ arguments: [String]) -> ObsidianCLIAnswer? {
    let name = Thread.current.name ?? ""
    lock.withLock { names.append(name) }
    return ObsidianCLIAnswer(status: 0, output: "")
  }
}
