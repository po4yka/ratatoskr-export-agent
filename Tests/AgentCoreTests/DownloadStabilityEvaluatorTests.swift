import AgentCore
import XCTest

final class DownloadStabilityEvaluatorTests: XCTestCase {
  private let quietInterval: TimeInterval = 30
  private let epoch = Date(timeIntervalSinceReferenceDate: 0)

  private func makeEvaluator() -> DownloadStabilityEvaluator {
    DownloadStabilityEvaluator(quietInterval: quietInterval)
  }

  func testQuietFileCrossingFullIntervalIsStable() {
    let evaluator = makeEvaluator()
    let written = FileSnapshot(byteSize: 1024, modifiedAt: epoch)

    let beforeInterval = evaluator.evaluate(
      baselineSnapshot: written,
      baselineSince: epoch,
      current: written,
      now: epoch.addingTimeInterval(quietInterval - 1),
      writerHoldDetected: false
    )
    XCTAssertEqual(beforeInterval, .pending, "an unchanged file below the interval stays pending")

    let atInterval = evaluator.evaluate(
      baselineSnapshot: written,
      baselineSince: epoch,
      current: written,
      now: epoch.addingTimeInterval(quietInterval),
      writerHoldDetected: false
    )
    guard case .stable(let evidence) = atInterval else {
      return XCTFail("a fully quiet file crossing the interval must become stable")
    }
    XCTAssertEqual(evidence.quietDuration, quietInterval, accuracy: 0.001)
    XCTAssertEqual(evidence.snapshot, written, "evidence carries the stable snapshot")
  }

  func testGrowingFileStaysPending() {
    let evaluator = makeEvaluator()
    let written = FileSnapshot(byteSize: 100, modifiedAt: epoch)
    let grown = FileSnapshot(byteSize: 250, modifiedAt: epoch.addingTimeInterval(5))

    let verdict = evaluator.evaluate(
      baselineSnapshot: written,
      baselineSince: epoch,
      current: grown,
      now: epoch.addingTimeInterval(quietInterval + 10),
      writerHoldDetected: false
    )
    XCTAssertEqual(verdict, .pending, "a growing file must never become stable while it grows")
  }

  func testModificationTimeTouchRestartsClock() {
    let evaluator = makeEvaluator()
    let written = FileSnapshot(byteSize: 100, modifiedAt: epoch)
    let touched = FileSnapshot(byteSize: 100, modifiedAt: epoch.addingTimeInterval(10))

    let verdict = evaluator.evaluate(
      baselineSnapshot: written,
      baselineSince: epoch,
      current: touched,
      now: epoch.addingTimeInterval(quietInterval + 20),
      writerHoldDetected: false
    )
    XCTAssertEqual(
      verdict, .pending,
      "a modification-time change without growth still resets the quiet clock")
  }

  func testChangedSnapshotRestartsQuietIntervalFromChange() {
    let evaluator = makeEvaluator()
    let written = FileSnapshot(byteSize: 100, modifiedAt: epoch)
    let final = FileSnapshot(byteSize: 200, modifiedAt: epoch.addingTimeInterval(10))

    // Growth stopped at t+10; one full interval later the file may stabilise.
    let before = evaluator.evaluate(
      baselineSnapshot: final,
      baselineSince: epoch.addingTimeInterval(10),
      current: final,
      now: epoch.addingTimeInterval(10 + quietInterval - 1),
      writerHoldDetected: false
    )
    XCTAssertEqual(before, .pending, "the interval restarts from the last change")

    let after = evaluator.evaluate(
      baselineSnapshot: final,
      baselineSince: epoch.addingTimeInterval(10),
      current: final,
      now: epoch.addingTimeInterval(10 + quietInterval),
      writerHoldDetected: false
    )
    guard case .stable(let evidence) = after else {
      return XCTFail("a full interval measured from the last change must stabilise")
    }
    XCTAssertEqual(evidence.quietDuration, quietInterval, accuracy: 0.001)
  }

  func testDetectedWriterHoldBlocksQueueingDespiteQuietMetadata() {
    let evaluator = makeEvaluator()
    let written = FileSnapshot(byteSize: 512, modifiedAt: epoch)

    let held = evaluator.evaluate(
      baselineSnapshot: written,
      baselineSince: epoch,
      current: written,
      now: epoch.addingTimeInterval(quietInterval),
      writerHoldDetected: true
    )
    XCTAssertEqual(
      held, .pending,
      "a detected writer hold keeps the candidate pending despite quiet metadata")

    let probePassed = evaluator.evaluate(
      baselineSnapshot: written,
      baselineSince: epoch,
      current: written,
      now: epoch.addingTimeInterval(quietInterval),
      writerHoldDetected: false
    )
    guard case .stable = probePassed else {
      return XCTFail("the identical sequence without a writer hold must stabilise")
    }
  }
}
