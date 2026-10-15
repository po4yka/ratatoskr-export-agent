import AgentCore
import XCTest

/// A result survives a restart, an operation that is already in the vault
/// is recognised by its expected hash, and a kept result that notes refuses
/// is dropped.
final class ObsidianCliRestartTests: ObsidianCliTestCase {
  private let succeeded = #"{"operation_id":"00000000-0000-7000-8000-0000000000b1","state":"succeeded"}"#
  private let unavailable = #"{"code":"notes.service.unavailable","message":"m","retryable":true}"#

  func testAKeptResultSurvivesARestart() async throws {
    try write("plain", to: "P.md")
    let apply = try fakeObsidian(running: true, cases: "property:set) printf '\\nstatus: done' >> '\(vault.path)/P.md' ;;")
    let set = sized(
      operation(kind: "set_property", path: "P.md", target: nil, base: sha("plain"), content: sha(#""done""#), property: ("status", "set")), 6
    )
    let server = queue([set], results: [(503, unavailable)])
    server.script("/content", status: 200, body: #""done""#)
    let store = FileDeviceResultStore(fileURL: root.appendingPathComponent("Support/device-results.json"))

    _ = try? await stored(server, store).applyQueuedOperations(apply)
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(set)],"next_cursor":"1"}"#)
    server.script("/result", status: 200, body: succeeded)
    let afterRestart = try await stored(server, store).applyQueuedOperations(apply)

    XCTAssertEqual(afterRestart, .answered(1))
    XCTAssertEqual(results(server).last, ["outcome": "applied", "sha256": sha("plain\nstatus: done")], "the kept result, not a new apply")
    XCTAssertEqual(try invocations().filter { $0.contains("property:set") }.count, 1)
  }

  func testAMovedFileWithItsExpectedHashIsAlreadyApplied() async throws {
    try write("[[Apollo]] links itself", to: "Projects/Apollo.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let rename = operation(kind: "rename", path: "Projects/Alpha.md", target: "Projects/Apollo.md", base: sha("[[Alpha]] links itself"))
      .replacingOccurrences(of: #""expected_sha256":null"#, with: #""expected_sha256":"\#(sha("[[Apollo]] links itself"))""#)
    let server = queue(rename)

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("[[Apollo]] links itself")])
    XCTAssertEqual(try invocations(), [["version"]])
  }

  func testAKeptResultThatNotesRefusesIsDroppedAndAppliedAgain() async throws {
    try write("alpha", to: "A.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let update = operation(kind: "update", path: "A.md", target: nil, base: sha("alpha"), content: sha("beta"))
    let server = queue([update], results: [(503, unavailable)])
    server.script("/content", status: 200, body: "beta")
    let client = client(server)

    _ = try? await client.applyQueuedOperations(apply)
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(update)],"next_cursor":"1"}"#)
    server.script("/result", status: 400, body: #"{"code":"notes.request.invalid","message":"m","retryable":false}"#)
    _ = try? await client.applyQueuedOperations(apply)
    try write("gamma", to: "A.md")
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(update)],"next_cursor":"1"}"#)
    server.script("/result", status: 200, body: succeeded)
    let third = try await client.applyQueuedOperations(apply)

    XCTAssertEqual(third, .answered(1))
    XCTAssertEqual(results(server).last, ["outcome": "base_mismatch", "local_sha256": sha("gamma")], "a new apply, not the refused result")
  }

  private func stored(_ server: FakeNotesServer, _ store: FileDeviceResultStore) -> NotesChannelClient {
    NotesChannelClient(
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture", connectionID: connection,
      resultStore: store, manifest: { VaultManifest(index: [:]) }
    )
  }
}
