import AgentCore
import XCTest

/// A rename whose links notes rewrites is one group: the agent checks the
/// base of each linking note first and reports the hash of each after the
/// CLI (workspace spec `notes-link-rewrite`).
final class ObsidianCliRewriteTests: ObsidianCliTestCase {
  private let renamed = "mv '%@/Projects/Alpha.md' '%@/Projects/Apollo.md'"

  func testRenameReportsTheHashOfEachLinkingNote() async throws {
    try write("alpha", to: "Projects/Alpha.md")
    try write("[[Alpha]]", to: "Index.md")
    try write("see [[Alpha]]", to: "Other.md")
    let apply = try fakeObsidian(
      running: true,
      cases: "rename) \(String(format: renamed, vault.path, vault.path)) && printf '[[Apollo]]' > '\(vault.path)/Index.md'"
        + " && printf 'see [[Apollo]]' > '\(vault.path)/Other.md' ;;"
    )
    let server = queue(grouped(
      operation(kind: "rename", path: "Projects/Alpha.md", target: "Projects/Apollo.md", base: sha("alpha")),
      [
        LinkingNote(path: "Index.md", base: sha("[[Alpha]]"), expected: sha("[[Apollo]]")),
        LinkingNote(path: "Other.md", base: sha("see [[Alpha]]"), expected: sha("see [[Apollo|Apollo]]")),
      ]
    ))

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(
      groupResults(server).first as? NSDictionary,
      [
        "outcome": "applied", "sha256": sha("alpha"),
        "rewrites": [
          ["outcome": "applied", "path": "Index.md", "sha256": sha("[[Apollo]]")],
          ["outcome": "applied", "path": "Other.md", "sha256": sha("see [[Apollo]]")],
        ],
      ] as NSDictionary
    )
    let routes = server.routes
    XCTAssertEqual(routes.filter { $0.hasSuffix("/finalize") }.count, 1, "only the note whose hash is not the expected hash is uploaded")
    XCTAssertLessThan(
      routes.firstIndex { $0.hasSuffix("/finalize") } ?? .max, routes.firstIndex { $0.hasSuffix("/result") } ?? .min,
      "the bytes are uploaded before the result"
    )
  }

  func testARewriteBaseMismatchRefusesTheGroupBeforeTheCLI() async throws {
    try write("alpha", to: "Projects/Alpha.md")
    try write("[[Alpha]] and a newer edit", to: "Index.md")
    let apply = try fakeObsidian(running: true, cases: "rename) \(String(format: renamed, vault.path, vault.path)) ;;")
    let server = queue(grouped(
      operation(kind: "rename", path: "Projects/Alpha.md", target: "Projects/Apollo.md", base: sha("alpha")),
      [LinkingNote(path: "Index.md", base: sha("[[Alpha]]"), expected: sha("[[Apollo]]"))]
    ))
    let sent = RewriteChanges()

    let pass = try await client(server).applyQueuedOperations(apply) { sent.add($0) }

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(groupResults(server).first as? NSDictionary, ["outcome": "base_mismatch"] as NSDictionary)
    XCTAssertEqual(try invocations(), [["version"]], "nothing of the group is changed")
    XCTAssertEqual(read("Projects/Alpha.md"), "alpha")
    XCTAssertEqual(sent.changes.map(\.path), ["Index.md"], "the newer linking note goes to the change buffer")
  }

  func testAnUnsafeRewritePathFailsTheGroup() async throws {
    try write("alpha", to: "Projects/Alpha.md")
    let apply = try fakeObsidian(running: true, cases: "rename) \(String(format: renamed, vault.path, vault.path)) ;;")
    let server = queue(grouped(
      operation(kind: "rename", path: "Projects/Alpha.md", target: "Projects/Apollo.md", base: sha("alpha")),
      [LinkingNote(path: "../Index.md", base: sha("[[Alpha]]"), expected: sha("[[Apollo]]"))]
    ))

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(groupResults(server).first as? NSDictionary, ["outcome": "failed", "code": "notes.write.unsafe_path"] as NSDictionary)
    XCTAssertEqual(try invocations(), [["version"]])
  }

  /// The operation with the list `rewrites` of its group.
  private func grouped(_ operation: String, _ rewrites: [LinkingNote]) -> String {
    let list = rewrites.map { #"{"base_hash":"\#($0.base)","expected_sha256":"\#($0.expected)","path":"\#($0.path)"}"# }
    return String(operation.dropLast()) + #","rewrites":[\#(list.joined(separator: ","))]}"#
  }

  /// The result bodies as JSON objects, with their nested lists.
  private func groupResults(_ server: FakeNotesServer) -> [Any] {
    server.log.filter { $0.path.hasSuffix("/result") }.compactMap { try? JSONSerialization.jsonObject(with: $0.body ?? Data()) }
  }
}

/// One linking note of a rename group, as the queue lists it.
private struct LinkingNote {
  let path: String
  let base: String
  let expected: String
}

/// The changes that the pass gives to the change buffer.
private final class RewriteChanges: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [VaultChange] = []

  var changes: [VaultChange] { lock.withLock { stored } }

  func add(_ changes: [VaultChange]) {
    lock.withLock { stored += changes }
  }
}
