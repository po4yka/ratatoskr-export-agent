import AgentCore
import CryptoKit
import XCTest

/// The `cli` channel applies the queue of its connection through a fake
/// `obsidian` executable that records its arguments. The real CLI, the
/// Obsidian app and the owner's vaults are never used.
final class ObsidianCliApplyTests: XCTestCase {
  private var root: URL!
  private var vault: URL { root.appendingPathComponent("Vault") }
  private var log: URL { root.appendingPathComponent("obsidian.log") }
  private let connection = "00000000-0000-7000-8000-000000000001"
  private let operationID = "00000000-0000-7000-8000-0000000000b1"

  override func setUpWithError() throws {
    root = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
  }

  override func tearDown() {
    if let root {
      try? FileManager.default.removeItem(at: root)
    }
  }

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

  // MARK: - Fixtures

  private func write(_ text: String, to path: String) throws {
    let file = vault.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  /// A fake `obsidian` that appends each argument on one line, then `--`,
  /// and runs the shell `cases` on the command (the second argument).
  private func fakeObsidian(running: Bool, cases: String) throws -> ObsidianCLIApply {
    let executable = root.appendingPathComponent("obsidian")
    let script = """
      #!/bin/sh
      { for argument in "$@"; do printf '%s\\n' "$argument"; done; printf -- '--\\n'; } >> '\(log.path)'
      case "$2" in
      \(cases)
      esac
      exit 0

      """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    return ObsidianCLIApply(
      vault: vault, vaultName: "Fixture", runner: ProcessObsidianCLIRunner(candidates: [executable.path], timeLimit: 10),
      obsidianRunning: { running }
    )
  }

  /// Each run of the fake, as its list of arguments.
  private func invocations() throws -> [[String]] {
    guard FileManager.default.fileExists(atPath: log.path) else {
      return []
    }
    let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
    return lines.split(separator: "--").map { $0.map(String.init) }.filter { !$0.isEmpty }
  }

  private func queue(_ operation: String) -> FakeNotesServer {
    let server = FakeNotesServer()
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(operation)],"next_cursor":"1"}"#)
    server.script("/result", status: 200, body: #"{"operation_id":"\#(operationID)","state":"succeeded"}"#)
    return server
  }

  private func operation(kind: String, path: String, target: String?, base: String?, content: String? = nil) -> String {
    let blob = content.map {
      #"{"owner_service":"ratatoskr-notes","digest":{"algorithm":"sha256","hex":"\#($0)"},"#
        + #""media_type":"text/markdown","length_bytes":4}"#
    }
    let fields: [String: Any] = [
      "operation_id": operationID, "cursor": "1", "kind": kind, "path": path, "target_path": target ?? NSNull(),
      "base_hash": base ?? NSNull(), "content": "CONTENT", "property_key": NSNull(), "property_change": NSNull(),
      "expected_sha256": NSNull(),
    ]
    let data = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
    return (String(bytes: data, encoding: .utf8) ?? "").replacingOccurrences(of: #""CONTENT""#, with: blob ?? "null")
  }

  private func client(_ server: FakeNotesServer) -> NotesChannelClient {
    NotesChannelClient(
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture", connectionID: connection,
      manifest: { VaultManifest(index: [:]) }
    )
  }

  /// The body of the one result that the agent sent.
  private func result(_ server: FakeNotesServer) -> [String: String] {
    let sent = server.log.filter { $0.path.hasSuffix("/result") }
    XCTAssertEqual(sent.count, 1, "one result for the one operation")
    return (try? JSONDecoder().decode([String: String].self, from: sent.first?.body ?? Data())) ?? [:]
  }

  private func sha(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
