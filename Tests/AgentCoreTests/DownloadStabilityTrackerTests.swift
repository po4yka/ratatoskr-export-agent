import AgentCore
import XCTest

/// A virtual clock handed to the tracker so quiet periods are exact.
private final class VirtualClock: @unchecked Sendable {
  var now: Date

  init(now: Date) {
    self.now = now
  }
}

final class DownloadStabilityTrackerTests: XCTestCase {
  private static let quietInterval: TimeInterval = 30
  private let referenceEpoch = Date(timeIntervalSinceReferenceDate: 1_000_000)
  private var directory: URL!
  private var clock: VirtualClock!

  override func setUpWithError() throws {
    directory = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    clock = VirtualClock(now: referenceEpoch)
  }

  override func tearDown() {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  func testSuffixedPathIsNeverQueuedDespiteFullQuietEvidence() throws {
    let file = try writeFile(named: "export.zip.download")
    var tracker = makeTracker()

    let assessment = tracker.assess(path: file.path)

    XCTAssertEqual(
      assessment, .rejected(.temporarySuffix),
      "a temporary-suffixed path must be refused no matter how quiet its evidence")
  }

  func testFirstObservationOfFreshPathIsPending() throws {
    let file = try writeFile(named: "export.zip")
    var tracker = makeTracker()

    let assessment = tracker.assess(path: file.path)

    XCTAssertEqual(
      assessment, .pending,
      "a freshly discovered path must wait at least one full quiet interval")
  }

  func testStablePathEmitsExactlyOneStableOutcomeOnRepeatedAssessments() throws {
    let file = try writeFile(named: "export.zip")
    var tracker = makeTracker()

    _ = tracker.assess(path: file.path)
    clock.now = referenceEpoch.addingTimeInterval(Self.quietInterval)
    let verdict = tracker.assess(path: file.path)
    guard case .stable(let candidate) = verdict else {
      return XCTFail("a file unchanged across the whole interval must stabilise")
    }
    XCTAssertEqual(candidate.url, file)
    XCTAssertEqual(candidate.snapshot.byteSize, payload.count)

    clock.now = referenceEpoch.addingTimeInterval(Self.quietInterval + 5)
    XCTAssertEqual(
      tracker.assess(path: file.path), .stable(candidate),
      "re-assessing an already-stable unchanged file repeats the identical outcome")
  }

  func testVanishedPathResetsTrackingSoReappearanceStartsFresh() throws {
    let file = try writeFile(named: "export.zip")
    var tracker = makeTracker()
    _ = tracker.assess(path: file.path)

    try FileManager.default.removeItem(at: file)
    clock.now = referenceEpoch.addingTimeInterval(10)
    XCTAssertEqual(tracker.assess(path: file.path), .pending, "a vanished path is never queued")

    try writeFile(named: "export.zip")
    clock.now = referenceEpoch.addingTimeInterval(35)
    XCTAssertEqual(
      tracker.assess(path: file.path), .pending,
      "a reappeared path starts a fresh quiet cycle, not the old one")

    clock.now = referenceEpoch.addingTimeInterval(65)
    guard case .stable = tracker.assess(path: file.path) else {
      return XCTFail("the fresh cycle completes one full interval after reappearance")
    }
  }

  func testRenamedInFileWaitsFullIntervalFromFirstSight() throws {
    let file = try writeFile(named: "export.zip")
    // A browser rename preserves the old modification time; discovery is now.
    try FileManager.default.setAttributes(
      [.modificationDate: referenceEpoch.addingTimeInterval(-3_600)],
      ofItemAtPath: file.path
    )
    var tracker = makeTracker()

    XCTAssertEqual(
      tracker.assess(path: file.path), .pending,
      "an ancient modification time must not shortcut the quiet period")

    clock.now = referenceEpoch.addingTimeInterval(Self.quietInterval)
    guard case .stable = tracker.assess(path: file.path) else {
      return XCTFail("one full quiet interval after first sight the file stabilises")
    }
  }

  func testGrowingFileAcrossAppendsStaysPendingUntilQuiet() throws {
    let file = try writeFile(named: "export.zip", content: payload)
    var tracker = makeTracker()
    _ = tracker.assess(path: file.path)

    try append(to: file, bytes: 64)
    clock.now = referenceEpoch.addingTimeInterval(15)
    XCTAssertEqual(tracker.assess(path: file.path), .pending, "growth keeps the file pending")

    try append(to: file, bytes: 32)
    clock.now = referenceEpoch.addingTimeInterval(40)
    XCTAssertEqual(tracker.assess(path: file.path), .pending, "each change restarts the clock")

    clock.now = referenceEpoch.addingTimeInterval(70)
    guard case .stable = tracker.assess(path: file.path) else {
      return XCTFail("one full interval after the final change the file stabilises")
    }
  }

  // MARK: - Helpers

  private var payload: Data {
    Data(repeating: 7, count: 128)
  }

  private func writeFile(
    named name: String, content: Data = Data(repeating: 7, count: 128)
  ) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try content.write(to: url, options: .atomic)
    return url
  }

  private func append(to url: URL, bytes count: Int) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer {
      try? handle.close()
    }
    try handle.write(contentsOf: Data(repeating: 9, count: count))
  }

  private func makeTracker() -> DownloadStabilityTracker {
    DownloadStabilityTracker(
      metadata: FileManagerMetadataProvider(),
      evaluator: DownloadStabilityEvaluator(quietInterval: Self.quietInterval),
      gate: CandidateEligibilityGate(maxArchiveBytes: 1_000_000),
      now: { [clock] in
        clock?.now ?? Self.fallbackEpoch
      }
    )
  }

  private static var fallbackEpoch: Date {
    Date(timeIntervalSinceReferenceDate: 1_000_000)
  }
}
