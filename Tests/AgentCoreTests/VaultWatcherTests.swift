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

  func testFolderRenameOfIdenticalFilesKeepsEachPathPair() {
    var watcher = VaultWatcher(firstSequence: 1)
    let empty = String(repeating: "e3", count: 32)

    for name in ["A.md", "B.md", "C.md"] {
      watcher.record(.deleted(path: "Old/\(name)", sha256: empty), at: start)
    }
    for name in ["C.md", "A.md", "B.md"] {
      watcher.record(.created(path: "New/\(name)", sha256: empty, byteLength: 0), at: start.addingTimeInterval(1))
    }

    XCTAssertEqual(
      watcher.drain(at: start.addingTimeInterval(1)).map { "\($0.previousPath ?? "-") -> \($0.path)" },
      ["Old/C.md -> New/C.md", "Old/A.md -> New/A.md", "Old/B.md -> New/B.md"],
      "a folder rename pairs each file with the file of the same name, never across names"
    )
  }

  func testSamePathIsPreferredOverAnotherPathWithTheSameHash() {
    var watcher = VaultWatcher(firstSequence: 1)

    watcher.record(.deleted(path: "B.md", sha256: digest), at: start)
    watcher.record(.deleted(path: "A.md", sha256: digest), at: start)
    watcher.record(.created(path: "A.md", sha256: digest, byteLength: 3), at: start.addingTimeInterval(1))

    XCTAssertEqual(
      watcher.drain(at: start.addingTimeInterval(5)),
      [
        VaultChange(sequence: 1, kind: .deleted, path: "B.md"),
        VaultChange(sequence: 2, kind: .updated, path: "A.md", sha256: digest, byteLength: 3),
      ],
      "a path written again pairs with its own delete, not with another delete of the same hash"
    )
  }

  func testCreateThenDeleteInsideWindowSendsNothing() {
    var watcher = VaultWatcher(firstSequence: 1)

    watcher.record(.created(path: "Draft.md", sha256: digest, byteLength: 3), at: start)
    watcher.record(.deleted(path: "Draft.md", sha256: digest), at: start.addingTimeInterval(2))

    XCTAssertEqual(watcher.drain(at: start.addingTimeInterval(9)), [], "a file created and deleted inside 3 seconds is not sent")
  }
}

private struct FixedRenameCheck: VaultRenameChecking {
  let answer: VaultRenameVerdict

  func verdict(renaming oldPath: String, to newPath: String) -> VaultRenameVerdict {
    answer
  }
}
