import AgentCore
import CryptoKit
import XCTest

/// A temporary vault, a fake `obsidian` executable that records its
/// arguments, and a `FakeNotesServer` with a queue. The real CLI, the
/// Obsidian app and the owner's vaults are never used.
class ObsidianCliTestCase: XCTestCase {
  var root: URL!
  var vault: URL { root.appendingPathComponent("Vault") }
  var log: URL { root.appendingPathComponent("obsidian.log") }
  let connection = "00000000-0000-7000-8000-000000000001"
  let operationID = "00000000-0000-7000-8000-0000000000b1"

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

  func write(_ text: String, to path: String) throws {
    let file = vault.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: file)
  }

  func read(_ path: String) -> String? {
    try? String(contentsOf: vault.appendingPathComponent(path), encoding: .utf8)
  }

  /// A fake `obsidian` that appends each argument on one line, then `--`,
  /// and runs the shell `cases` on the command (the second argument).
  func fakeObsidian(
    running: Bool, cases: String, settle: @escaping @Sendable () async -> Void = {}
  ) throws -> ObsidianCLIApply {
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
      obsidianRunning: { running }, settle: settle
    )
  }

  /// Each run of the fake, as its list of arguments.
  func invocations() throws -> [[String]] {
    guard FileManager.default.fileExists(atPath: log.path) else {
      return []
    }
    let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
    return lines.split(separator: "--").map { $0.map(String.init) }.filter { !$0.isEmpty }
  }

  /// A server whose queue holds `operations` and that answers each result
  /// with the next of `results` (by default one `200` per operation).
  func queue(_ operations: [String], results: [(status: Int, body: String)]? = nil) -> FakeNotesServer {
    let server = FakeNotesServer()
    let list = operations.joined(separator: ",")
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(list)],"next_cursor":"1"}"#)
    let succeeded = #"{"operation_id":"\#(operationID)","state":"succeeded"}"#
    for answer in results ?? operations.map({ _ in (200, succeeded) }) {
      server.script("/result", status: answer.status, body: answer.body)
    }
    return server
  }

  func queue(_ operation: String) -> FakeNotesServer {
    queue([operation])
  }

  func operation(
    kind: String, path: String, target: String?, base: String?, content: String? = nil, property: (String, String)? = nil
  ) -> String {
    let blob = content.map {
      #"{"owner_service":"ratatoskr-notes","digest":{"algorithm":"sha256","hex":"\#($0)"},"#
        + #""media_type":"text/markdown","length_bytes":4}"#
    }
    let fields: [String: Any] = [
      "operation_id": operationID, "cursor": "1", "kind": kind, "path": path, "target_path": target ?? NSNull(),
      "base_hash": base ?? NSNull(), "content": "CONTENT", "property_key": property?.0 ?? NSNull(),
      "property_change": property?.1 ?? NSNull(), "expected_sha256": NSNull(),
    ]
    let data = (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
    return (String(bytes: data, encoding: .utf8) ?? "").replacingOccurrences(of: #""CONTENT""#, with: blob ?? "null")
  }

  func client(_ server: FakeNotesServer) -> NotesChannelClient {
    NotesChannelClient(
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture", connectionID: connection,
      manifest: { VaultManifest(index: [:]) }
    )
  }

  /// The bodies of the results that the agent sent, in send order.
  func results(_ server: FakeNotesServer) -> [[String: String]] {
    server.log.filter { $0.path.hasSuffix("/result") }.map {
      (try? JSONDecoder().decode([String: String].self, from: $0.body ?? Data())) ?? [:]
    }
  }

  /// The body of the one result that the agent sent.
  func result(_ server: FakeNotesServer) -> [String: String] {
    let sent = results(server)
    XCTAssertEqual(sent.count, 1, "one result for the one operation")
    return sent.first ?? [:]
  }

  func sha(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
