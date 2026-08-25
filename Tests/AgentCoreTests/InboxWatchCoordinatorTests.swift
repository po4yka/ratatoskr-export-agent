import AgentCore
import XCTest

final class InboxWatchCoordinatorTests: XCTestCase {
  func testStartScansPreExistingFilesAndEmitsCandidateAfterQuietPeriod() async {
    let scenario = WatchScenario()
    let folderA = WatchScenario.folderURL(named: "inbox-a")
    let fileURL = scenario.addCandidate(named: "export.zip", in: folderA, byteSize: 512)
    let target = WatchedFolderTarget(id: UUID(), url: folderA, isEnabled: true)

    let passes = expectation(description: "initial pass plus reassessment pass")
    passes.expectedFulfillmentCount = 2
    passes.assertForOverFulfill = true
    let coordinator = scenario.makeCoordinator(targets: [target]) { passes.fulfill() }

    await coordinator.start()

    XCTAssertEqual(
      scenario.sink.all.count, 0,
      "a pre-existing file must not queue before the quiet interval completes")
    XCTAssertEqual(
      scenario.tickScheduler.pendingCount, 1,
      "the initial pass schedules exactly one reassessment")

    scenario.clock.advance(by: 30)
    scenario.tickScheduler.runPending()
    await fulfillment(of: [passes], timeout: 5)

    let emissions = scenario.sink.all
    XCTAssertEqual(emissions.count, 1, "exactly one stable candidate is delivered")
    XCTAssertEqual(emissions.first?.url, fileURL)
    XCTAssertEqual(emissions.first?.folderID, target.id)
    XCTAssertEqual(emissions.first?.evidence.quietDuration ?? -1, 30, accuracy: 0.001)
    XCTAssertEqual(emissions.first?.snapshot.byteSize, 512)
  }

  func testDisabledFolderIsNeverObserved() async {
    let scenario = WatchScenario()
    let folderA = WatchScenario.folderURL(named: "enabled")
    let folderB = WatchScenario.folderURL(named: "disabled")
    _ = scenario.addCandidate(named: "ignored.zip", in: folderB, byteSize: 100)
    let enabledTarget = WatchedFolderTarget(id: UUID(), url: folderA, isEnabled: true)
    let disabledTarget = WatchedFolderTarget(id: UUID(), url: folderB, isEnabled: false)

    let passes = expectation(description: "initial pass")
    passes.expectedFulfillmentCount = 1
    passes.assertForOverFulfill = true
    let coordinator = scenario.makeCoordinator(targets: [enabledTarget, disabledTarget]) {
      passes.fulfill()
    }

    await coordinator.start()

    XCTAssertEqual(
      scenario.requestedTargetIDs(), [enabledTarget.id],
      "only the enabled folder gets a platform monitor")
    let enabledStatus = await coordinator.status(for: enabledTarget.id)
    XCTAssertEqual(enabledStatus, .watching)
    let disabledStatus = await coordinator.status(for: disabledTarget.id)
    XCTAssertNil(
      disabledStatus,
      "a disabled folder has no watch state at all")

    scenario.clock.advance(by: 30)
    XCTAssertTrue(
      scenario.sink.all.isEmpty,
      "no candidate may ever originate from a disabled folder, whatever time passes")
    await fulfillment(of: [passes], timeout: 5)
  }
}
