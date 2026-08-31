import AgentCore
import XCTest

final class InboxWatchCoordinatorLifecycleTests: XCTestCase {
  func testStopWaitsForTrackedCandidateProcessingToFinish() async {
    let scenario = WatchScenario()
    let folder = WatchScenario.folderURL(named: "blocking-processing")
    _ = scenario.addCandidate(named: "export.zip", in: folder, byteSize: 256)
    let gate = BlockingCandidateProcessing()
    let coordinator = scenario.makeCoordinator(
      targets: [WatchedFolderTarget(id: UUID(), url: folder, isEnabled: true)],
      candidateHandler: { candidate in await gate.process(candidate) }
    )
    await coordinator.start()
    scenario.clock.advance(by: 30)
    scenario.tickScheduler.runPending()
    await gate.waitUntilStarted()

    let stopped = CompletionFlag()
    let stopTask = Task {
      await coordinator.stop()
      await stopped.markCompleted()
    }
    for _ in 0..<100 { await Task.yield() }
    let completedBeforeRelease = await stopped.isCompleted
    XCTAssertFalse(completedBeforeRelease)

    await gate.release()
    await stopTask.value
    let completedAfterRelease = await stopped.isCompleted
    XCTAssertTrue(completedAfterRelease)
  }

  func testReplacingTargetsStartsTheNewLiveRegistryFolder() async {
    let scenario = WatchScenario()
    let original = WatchedFolderTarget(
      id: UUID(), url: WatchScenario.folderURL(named: "original"), isEnabled: true
    )
    let added = WatchedFolderTarget(
      id: UUID(), url: WatchScenario.folderURL(named: "added"), isEnabled: true
    )
    let coordinator = scenario.makeCoordinator(targets: [original])
    await coordinator.start()

    await coordinator.replaceTargets([original, added])

    XCTAssertEqual(scenario.requestedTargetIDs(), [original.id, added.id])
    let addedStatus = await coordinator.status(for: added.id)
    XCTAssertEqual(addedStatus, .watching)
    await coordinator.stop()
  }

  func testUnavailableFolderAtStartDegradesAloneWhileOtherStillYieldsCandidates() async {
    let scenario = WatchScenario()
    let folderA = WatchScenario.folderURL(named: "vanished")
    let folderB = WatchScenario.folderURL(named: "healthy")
    let healthyFile = scenario.addCandidate(named: "export.zip", in: folderB, byteSize: 256)
    scenario.failListing(of: folderA, code: .fileNoSuchFile)
    let (aID, bID) = (UUID(), UUID())
    let passes = PassCounter()

    let coordinator = scenario.makeCoordinator(targets: [
      WatchedFolderTarget(id: aID, url: folderA, isEnabled: true),
      WatchedFolderTarget(id: bID, url: folderB, isEnabled: true),
    ]) { passes.bump() }

    await coordinator.start()
    await waitForPasses(1, passes)

    let aStatusAfterStart = await coordinator.status(for: aID)
    XCTAssertEqual(
      aStatusAfterStart, .degraded(.missing),
      "a missing folder degrades at start with its reason")
    let bStatusAfterStart = await coordinator.status(for: bID)
    XCTAssertEqual(bStatusAfterStart, .watching)

    scenario.clock.advance(by: 30)
    scenario.tickScheduler.runPending()
    await waitForPasses(2, passes)

    XCTAssertEqual(
      scenario.sink.all.map(\.url), [healthyFile],
      "only the healthy folder produces candidates")
  }

  func testUnstartableMonitorDegradesItsFolderAlone() async {
    let scenario = WatchScenario()
    let folderA = WatchScenario.folderURL(named: "fine")
    let folderC = WatchScenario.folderURL(named: "broken-monitor")
    let aID = UUID()
    let cID = UUID()
    scenario.failMonitorStart(CocoaError(.featureUnsupported), for: cID)
    let passes = PassCounter()

    let coordinator = scenario.makeCoordinator(targets: [
      WatchedFolderTarget(id: aID, url: folderA, isEnabled: true),
      WatchedFolderTarget(id: cID, url: folderC, isEnabled: true),
    ]) { passes.bump() }

    await coordinator.start()
    await waitForPasses(1, passes)

    let cStatusAfterStart = await coordinator.status(for: cID)
    XCTAssertEqual(
      cStatusAfterStart, .degraded(.monitorFailed),
      "a monitor that cannot start degrades its own folder only")
    let aStatusAfterStart = await coordinator.status(for: aID)
    XCTAssertEqual(aStatusAfterStart, .watching)
  }
}

private actor BlockingCandidateProcessing {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func process(_: StableArchiveCandidate) async -> Bool {
    started = true
    startWaiters.forEach { $0.resume() }
    startWaiters.removeAll()
    await withCheckedContinuation { releaseContinuation = $0 }
    return false
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func release() {
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private actor CompletionFlag {
  private(set) var isCompleted = false

  func markCompleted() { isCompleted = true }
}
