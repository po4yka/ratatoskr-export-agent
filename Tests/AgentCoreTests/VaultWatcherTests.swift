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

  func testCreateThenDeleteOneSecondLaterIsRename() {
    var watcher = VaultWatcher(firstSequence: 1)

    watcher.record(.created(path: "B.md", sha256: digest, byteLength: 3), at: start)
    watcher.record(.deleted(path: "A.md", sha256: digest), at: start.addingTimeInterval(1))

    XCTAssertEqual(
      watcher.drain(at: start.addingTimeInterval(1)),
      [VaultChange(sequence: 1, kind: .renamed, path: "B.md", previousPath: "A.md", sha256: digest, byteLength: 3)]
    )
  }

  func testEqualHashOutsideWindowIsNotPaired() {
    var watcher = VaultWatcher(firstSequence: 1)

    watcher.record(.deleted(path: "A.md", sha256: digest), at: start)
    watcher.record(.created(path: "B.md", sha256: digest, byteLength: 3), at: start.addingTimeInterval(3))

    XCTAssertEqual(watcher.drain(at: start.addingTimeInterval(2.9)), [], "an unpaired delete waits for the window")
    XCTAssertEqual(
      watcher.drain(at: start.addingTimeInterval(6)),
      [
        VaultChange(sequence: 1, kind: .deleted, path: "A.md"),
        VaultChange(sequence: 2, kind: .created, path: "B.md", sha256: digest, byteLength: 3),
      ]
    )
  }

  func testRefutedPairIsNotRename() {
    var watcher = VaultWatcher(firstSequence: 1, renameCheck: FixedRenameCheck(answer: .refuted))

    watcher.record(.deleted(path: "A.md", sha256: digest), at: start)
    watcher.record(.created(path: "B.md", sha256: digest, byteLength: 3), at: start.addingTimeInterval(1))

    XCTAssertEqual(watcher.drain(at: start.addingTimeInterval(9)).map(\.kind), [.deleted, .created])
  }

  func testUnavailableCheckKeepsHashPairing() {
    var watcher = VaultWatcher(firstSequence: 1, renameCheck: FixedRenameCheck(answer: .unavailable))

    watcher.record(.deleted(path: "A.md", sha256: digest), at: start)
    watcher.record(.created(path: "B.md", sha256: digest, byteLength: 3), at: start.addingTimeInterval(1))

    XCTAssertEqual(watcher.drain(at: start.addingTimeInterval(9)).map(\.kind), [.renamed])
  }

  func testDifferentHashesAreNotPaired() {
    var watcher = VaultWatcher(firstSequence: 1)

    watcher.record(.deleted(path: "A.md", sha256: digest), at: start)
    watcher.record(.created(path: "B.md", sha256: String(repeating: "cd", count: 32), byteLength: 3), at: start)

    XCTAssertEqual(watcher.drain(at: start.addingTimeInterval(9)).map(\.kind), [.deleted, .created])
  }

  func testSamePathDeletedAndWrittenAgainIsOneUpdate() {
    var watcher = VaultWatcher(firstSequence: 1)

    watcher.record(.deleted(path: "A.md", sha256: digest), at: start)
    watcher.record(.created(path: "A.md", sha256: digest, byteLength: 3), at: start)
    watcher.record(.created(path: "Tmp.md", sha256: digest, byteLength: 3), at: start)
    watcher.record(.deleted(path: "Tmp.md", sha256: digest), at: start)

    XCTAssertEqual(
      watcher.drain(at: start),
      [VaultChange(sequence: 1, kind: .updated, path: "A.md", sha256: digest, byteLength: 3)],
      "a file created and deleted inside the window is not sent"
    )
  }

  func testChangesLeaveInOrderWithConsecutiveSequences() {
    var watcher = VaultWatcher(firstSequence: 7)

    watcher.record(.modified(path: "A.md", sha256: digest, byteLength: 3), at: start)
    watcher.record(.created(path: "B.md", sha256: digest, byteLength: 3), at: start)
    watcher.record(.modified(path: "C.md", sha256: digest, byteLength: 3), at: start)

    XCTAssertEqual(watcher.drain(at: start).map(\.path), ["A.md"], "a later change waits behind an unpaired create")
    XCTAssertEqual(watcher.drain(at: start.addingTimeInterval(3)).map(\.sequence), [8, 9])
  }
}

private struct FixedRenameCheck: VaultRenameChecking {
  let answer: VaultRenameVerdict

  func verdict(renaming oldPath: String, to newPath: String) -> VaultRenameVerdict {
    answer
  }
}
