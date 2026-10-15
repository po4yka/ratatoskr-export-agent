import AgentCore
import XCTest

/// `set_property` runs `obsidian property:set` or `property:remove`.
final class ObsidianCliPropertyTests: ObsidianCliTestCase {
  func testSetPassesTheValueAndItsType() async throws {
    try write("plain", to: "P.md")
    let values = [("status", #""done""#), ("count", "3"), ("done", "true"), ("tags", #"["a","b"]"#)]
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(values.map {
      operation(kind: "set_property", path: "P.md", target: nil, base: sha("plain"), content: sha($0.1), property: ($0.0, "set"))
    })
    for value in values {
      server.script("/content", status: 200, body: value.1)
    }

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(values.count))
    XCTAssertEqual(
      try invocations().dropFirst().map { $0 },
      [
        ["vault=Fixture", "property:set", "name=status", "value=done", "path=P.md"],
        ["vault=Fixture", "property:set", "name=count", "value=3", "type=number", "path=P.md"],
        ["vault=Fixture", "property:set", "name=done", "value=true", "type=checkbox", "path=P.md"],
        ["vault=Fixture", "property:set", "name=tags", "value=a, b", "type=list", "path=P.md"],
      ]
    )
  }

  func testRemovePassesTheName() async throws {
    try write("plain", to: "P.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(operation(kind: "set_property", path: "P.md", target: nil, base: sha("plain"), property: ("status", "remove")))

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(try invocations().last, ["vault=Fixture", "property:remove", "name=status", "path=P.md"])
    XCTAssertEqual(result(server), ["outcome": "applied", "sha256": sha("plain")])
  }

  func testSetPropertyContentIsCheckedAgainstItsDigest() async throws {
    try write("plain", to: "P.md")
    let apply = try fakeObsidian(running: true, cases: "")
    let server = queue(
      operation(kind: "set_property", path: "P.md", target: nil, base: sha("plain"), content: sha(#""other""#), property: ("status", "set"))
    )
    server.script("/content", status: 200, body: #""done""#)

    let pass = try await client(server).applyQueuedOperations(apply)

    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(result(server), ["outcome": "failed", "code": "notes.channel.refused"])
    XCTAssertEqual(try invocations(), [["version"]], "bytes that do not match their digest are not applied")
  }
}
