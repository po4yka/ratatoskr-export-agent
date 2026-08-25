import AgentCore
import XCTest

final class FSEventsFolderMonitorTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testCreatedFileDeliversEventWithinWindow() throws {
    let delivered = expectation(description: "folder activity delivered")
    let monitor = FSEventsFolderMonitor(url: directory)
    try monitor.start(onActivity: { delivered.fulfill() })
    defer {
      monitor.stop()
    }

    // A download keeps writing for a while, so the fixture does too: a
    // single write could race the stream's asynchronous registration and
    // prove nothing except that timing is fragile.
    let target = directory.appendingPathComponent("export.zip")
    let writer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
    writer.schedule(deadline: .now(), repeating: 0.25)
    writer.setEventHandler {
      try? Data("synthetic-\(UUID().uuidString)".utf8).write(to: target, options: .atomic)
    }
    writer.resume()
    defer {
      writer.cancel()
    }

    wait(for: [delivered], timeout: 30)
  }

  func testStartOnMissingDirectoryFailsClosedWithoutCrashing() throws {
    let absent = URL(fileURLWithPath: "/watch-fixture/absent-\(UUID().uuidString)")
    let monitor = FSEventsFolderMonitor(url: absent)

    XCTAssertThrowsError(try monitor.start(onActivity: {})) { error in
      XCTAssertEqual(error as? FolderMonitorFailure, .folderUnavailable)
    }
    XCTAssertFalse(monitor.isObserving, "a refused start must not leave a live stream")
  }

  func testStopIsSafeToRepeat() throws {
    let monitor = FSEventsFolderMonitor(url: directory)
    try monitor.start(onActivity: {})

    monitor.stop()
    monitor.stop()

    XCTAssertFalse(monitor.isObserving, "repeated stops leave nothing observing")
  }
}
