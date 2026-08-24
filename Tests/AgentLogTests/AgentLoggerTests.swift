import XCTest

@testable import AgentLog

final class AgentLoggerTests: XCTestCase {
  func testDebugLevelIsRedactedLikeAnyLevel() throws {
    var logged: [String] = []
    let logger = AgentLogger(sink: { logged.append($0) })

    logger.debug("loaded settings from /Users/alice/private/inbox/settings.json today")

    let line = try XCTUnwrap(logged.first, "expected exactly one emitted line, got: \(logged)")

    XCTAssertTrue(
      line.contains("<path>"),
      "expected the debug line to contain the placeholder, got: \(line)"
    )
    XCTAssertFalse(
      line.contains("/Users/alice"),
      "expected the absolute path to be redacted, got: \(line)"
    )
  }

  func testVerboseToggleRevealsPathVerbatim() throws {
    var logged: [String] = []
    let logger = AgentLogger(sink: { logged.append($0) }, verbose: true)

    logger.debug("loaded settings from /Users/alice/private/inbox/settings.json today")

    let line = try XCTUnwrap(logged.first, "expected exactly one emitted line, got: \(logged)")

    XCTAssertTrue(
      line.contains("/Users/alice/private/inbox/settings.json"),
      "expected the verbose line to keep the path verbatim, got: \(line)"
    )
  }

  func testDefaultKeepsPlaceholder() throws {
    var logged: [String] = []
    let logger = AgentLogger(sink: { logged.append($0) })

    logger.info("parsed conversations.json successfully")

    let line = try XCTUnwrap(logged.first, "expected exactly one emitted line, got: \(logged)")

    XCTAssertTrue(
      line.contains("<path>"),
      "expected the default line to contain the placeholder, got: \(line)"
    )
    XCTAssertFalse(
      line.contains("conversations.json"),
      "expected the bare filename to be redacted, got: \(line)"
    )
  }
}
