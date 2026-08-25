import XCTest

@testable import AgentCore

final class InboxWatchCoordinatorDegradationTests: XCTestCase {
  func testFolderDeletedMidWatchDegradesWithoutStoppingOthers() async {
    let scenario = WatchScenario()
    let folderA = WatchScenario.folderURL(named: "removed-later")
    let folderB = WatchScenario.folderURL(named: "survivor")
    _ = scenario.addCandidate(named: "gone.zip", in: folderA, byteSize: 64)
    let survivingFile = scenario.addCandidate(named: "kept.zip", in: folderB, byteSize: 128)
    let (aID, bID) = (UUID(), UUID())
    let passes = PassCounter()

    let coordinator = scenario.makeCoordinator(targets: [
      WatchedFolderTarget(id: aID, url: folderA, isEnabled: true),
      WatchedFolderTarget(id: bID, url: folderB, isEnabled: true),
    ]) { passes.bump() }

    await coordinator.start()
    await waitForPasses(1, passes)

    scenario.failListing(of: folderA, code: .fileNoSuchFile)
    await coordinator.folderHadActivity()
    scenario.debounceScheduler.runPending()
    await waitForPasses(2, passes)

    let aStatusMidWatch = await coordinator.status(for: aID)
    XCTAssertEqual(
      aStatusMidWatch, .degraded(.missing),
      "the deleted folder degrades as soon as its scan notices")
    let bStatusMidWatch = await coordinator.status(for: bID)
    XCTAssertEqual(bStatusMidWatch, .watching)

    scenario.clock.advance(by: 30)
    scenario.tickScheduler.runPending()
    await waitForPasses(3, passes)

    XCTAssertEqual(
      scenario.sink.all.map(\.url), [survivingFile],
      "the degraded folder produces nothing; the survivor queues normally")
  }

  func testDuplicateNotificationsKeepSingleCandidateOutcome() async {
    let scenario = WatchScenario()
    let folderA = WatchScenario.folderURL(named: "inbox")
    let fileURL = scenario.addCandidate(named: "export.zip", in: folderA, byteSize: 900)
    let target = WatchedFolderTarget(id: UUID(), url: folderA, isEnabled: true)
    let passes = PassCounter()

    let coordinator = scenario.makeCoordinator(targets: [target]) { passes.bump() }

    await coordinator.start()
    await waitForPasses(1, passes)

    for _ in 0..<3 {
      await coordinator.folderHadActivity()
    }
    scenario.debounceScheduler.runPending()
    await waitForPasses(2, passes)

    scenario.clock.advance(by: 30)
    scenario.tickScheduler.runPending()
    await waitForPasses(3, passes)

    for _ in 0..<2 {
      await coordinator.folderHadActivity()
    }
    scenario.debounceScheduler.runPending()
    await waitForPasses(4, passes)

    XCTAssertEqual(
      scenario.sink.all.map(\.url), [fileURL],
      "repeated notifications and later bursts keep one candidate outcome")
    XCTAssertEqual(
      scenario.tickScheduler.pendingCount, 0,
      "no reassessment stays scheduled once the path reached its outcome")
  }

  func testStopEndsEmissionsAndIsIdempotent() async {
    let scenario = WatchScenario()
    let folderA = WatchScenario.folderURL(named: "inbox")
    _ = scenario.addCandidate(named: "export.zip", in: folderA, byteSize: 300)
    let target = WatchedFolderTarget(id: UUID(), url: folderA, isEnabled: true)
    let passes = PassCounter()

    let coordinator = scenario.makeCoordinator(targets: [target]) { passes.bump() }

    await coordinator.start()
    await waitForPasses(1, passes)
    await coordinator.stop()
    await coordinator.stop()

    let statusAfterStop = await coordinator.status(for: target.id)
    XCTAssertNil(statusAfterStop, "stop clears watch state")
    XCTAssertFalse(scenario.monitor(for: target.id)?.isStarted() ?? true)
    XCTAssertTrue(scenario.debounceScheduler.pendingCount == 0)

    scenario.monitor(for: target.id)?.simulateActivity()
    scenario.debounceScheduler.runPending()
    scenario.clock.advance(by: 30)
    scenario.tickScheduler.runPending()

    XCTAssertTrue(
      scenario.sink.all.isEmpty,
      "activity after stop must not produce candidates")
  }
}
