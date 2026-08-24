import XCTest

@testable import AgentLog

final class LogRedactorTests: XCTestCase {
  func testAbsolutePathReplacedWithPlaceholder() {
    let output = LogRedactor.redact(
      "loaded settings from /Users/alice/private/inbox/settings.json today")

    XCTAssertTrue(
      output.contains("<path>"),
      "expected the redacted message to contain the placeholder, got: \(output)")
    XCTAssertFalse(
      output.contains("/Users/alice"),
      "expected the absolute path prefix to be removed, got: \(output)")
    XCTAssertFalse(
      output.contains("settings.json"),
      "expected the final filename component to be absent, got: \(output)"
    )
  }

  func testHomeRelativePathRedacted() {
    let output = LogRedactor.redact("watching ~/Documents/inbox/export.zip for changes")

    XCTAssertTrue(
      output.contains("<path>"),
      "expected the redacted message to contain the placeholder, got: \(output)")
    XCTAssertFalse(
      output.contains("~/"), "expected the tilde-prefixed path to be removed, got: \(output)")
    XCTAssertFalse(
      output.contains("export.zip"), "expected the filename to be absent, got: \(output)")
  }

  func testBareFilenameWithExtensionRedacted() {
    let output = LogRedactor.redact("parsed conversations.json successfully")

    XCTAssertTrue(
      output.contains("<path>"),
      "expected the redacted message to contain the placeholder, got: \(output)")
    XCTAssertFalse(
      output.contains("conversations.json"),
      "expected the bare filename to be absent, got: \(output)"
    )
  }

  func testMessageWithoutPathsPassesThroughUnchanged() {
    let message = "upload queue drained with zero retries"

    XCTAssertEqual(
      LogRedactor.redact(message), message,
      "expected a message without paths to pass through unchanged")
  }
}
