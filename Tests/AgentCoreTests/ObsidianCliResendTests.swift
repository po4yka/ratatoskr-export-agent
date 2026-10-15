import AgentCore
import XCTest

/// A result that does not get `200` is sent again on the next pass, with
/// the same body: the operation stays in the queue.
final class ObsidianCliResendTests: ObsidianCliTestCase {
  private let succeeded = #"{"operation_id":"00000000-0000-7000-8000-0000000000b1","state":"succeeded"}"#

  func testAResultIsSentAgainAfterAServerError() async throws {
    try write("plain", to: "P.md")
    let apply = try fakeObsidian(running: true, cases: "property:set) printf '\\nstatus: done' >> '\(vault.path)/P.md' ;;")
    let set = sized(
      operation(kind: "set_property", path: "P.md", target: nil, base: sha("plain"), content: sha(#""done""#), property: ("status", "set")), 6
    )
    let server = queue([set], results: [(503, #"{"code":"notes.service.unavailable","message":"m","retryable":true}"#)])
    server.script("/content", status: 200, body: #""done""#)
    let client = client(server)

    let first = try? await client.applyQueuedOperations(apply)
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(set)],"next_cursor":"1"}"#)
    server.script("/result", status: 200, body: succeeded)
    server.script("/content", status: 200, body: #""done""#)
    let second = try await client.applyQueuedOperations(apply)

    XCTAssertNil(first, "a 5xx ends the pass")
    XCTAssertEqual(second, .answered(1))
    let sent = results(server)
    XCTAssertEqual(sent.count, 2)
    XCTAssertEqual(sent.last, ["outcome": "applied", "sha256": sha("plain\nstatus: done")], "the same result, not a base mismatch")
    XCTAssertEqual(try invocations().filter { $0.contains("property:set") }.count, 1, "the property is set once")
  }

  func testAResultIsSentAgainAfterANetworkError() async throws {
    try write("alpha", to: "Projects/Alpha.md")
    let apply = try fakeObsidian(running: true, cases: "rename) mv '\(vault.path)/Projects/Alpha.md' '\(vault.path)/Projects/Apollo.md' ;;")
    let rename = operation(kind: "rename", path: "Projects/Alpha.md", target: "Projects/Apollo.md", base: sha("alpha"))
    let server = queue([rename])
    let http = NetworkFailsOnce(server: server)
    let client = NotesChannelClient(
      http: http, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture", connectionID: connection,
      manifest: { VaultManifest(index: [:]) }
    )

    let first = try? await client.applyQueuedOperations(apply)
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(rename)],"next_cursor":"1"}"#)
    let second = try await client.applyQueuedOperations(apply)

    XCTAssertNil(first, "a network error ends the pass")
    XCTAssertEqual(second, .answered(1))
    XCTAssertEqual(results(server), [["outcome": "applied", "sha256": sha("alpha")]], "the one result that notes received")
    XCTAssertEqual(try invocations().filter { $0.contains("rename") }.count, 1, "the file is renamed once")
  }
}

/// Fails the first result with a network error, as a lost connection does.
private final class NetworkFailsOnce: NotesChannelHTTP, @unchecked Sendable {
  private let server: FakeNotesServer
  private let lock = NSLock()
  private var failed = false

  init(server: FakeNotesServer) {
    self.server = server
  }

  func perform(_ request: NotesChannelRequest) async throws -> NotesChannelAnswer {
    let fail = lock.withLock {
      guard request.path.hasSuffix("/result"), !failed else {
        return false
      }
      failed = true
      return true
    }
    if fail {
      throw URLError(.networkConnectionLost)
    }
    return try await server.perform(request)
  }
}
