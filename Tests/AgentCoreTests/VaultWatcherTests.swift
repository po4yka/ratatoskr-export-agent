import AgentCore
import XCTest

final class VaultWatcherTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 3_000_000)
  private let digest = String(repeating: "ab", count: 32)

  func testDeleteAndCreateWithEqualHashIsRename() {
    var watcher = VaultWatcher(firstSequence: 11)

    watcher.record(.deleted(path: "Notes/Old.md", sha256: digest), at: start)
    watcher.record(.created(path: "Notes/New.md", sha256: digest, byteLength: 12), at: start.addingTimeInterval(1))
    let changes = watcher.drain(at: start.addingTimeInterval(5))

    XCTAssertEqual(
      changes,
      [
        VaultChange(
          sequence: 11,
          kind: .renamed,
          path: "Notes/New.md",
          previousPath: "Notes/Old.md",
          sha256: digest,
          byteLength: 12
        ),
      ],
      "a delete and a create with equal hashes inside 3 seconds are one renamed change"
    )
  }
}
