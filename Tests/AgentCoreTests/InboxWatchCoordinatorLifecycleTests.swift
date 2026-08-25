import AgentCore
import XCTest

final class InboxWatchCoordinatorLifecycleTests: XCTestCase {
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
