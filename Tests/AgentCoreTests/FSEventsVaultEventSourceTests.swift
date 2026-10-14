import AgentCore
import XCTest

/// The one test against real FSEvents, on a temporary directory.
final class FSEventsVaultEventSourceTests: XCTestCase {
  private var vault: URL!

  override func setUpWithError() throws {
    vault = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let vault {
      try? FileManager.default.removeItem(at: vault)
    }
  }

  func testWrittenFileIsNamedByItsPath() throws {
    let named = expectation(description: "the written file is named")
    named.assertForOverFulfill = false
    let target = vault.appendingPathComponent("Note.md")
    let source = FSEventsVaultEventSource(root: vault, latency: 0.05)
    let expected = VaultScanner(root: vault).rootPath + "/Note.md"
    try source.start { paths, _ in
      if paths.contains(expected) {
        named.fulfill()
      }
    }
    defer {
      source.stop()
    }

    // Write more than once: a single write could race the asynchronous start
    // of the stream.
    let writer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
    writer.schedule(deadline: .now(), repeating: 0.25)
    writer.setEventHandler {
      try? Data("synthetic-\(UUID().uuidString)".utf8).write(to: target)
    }
    writer.resume()
    defer {
      writer.cancel()
    }

    wait(for: [named], timeout: 10)
  }
}
