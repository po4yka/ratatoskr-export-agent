import AgentCore
import XCTest

final class DebouncerTests: XCTestCase {
  private let epoch = Date(timeIntervalSinceReferenceDate: 2_000_000)

  func testBurstInsideWindowFiresOnceAtWindowEnd() {
    let scheduler = WatchManualScheduler()
    let clock = WatchVirtualClock(epoch)
    let probe = WorkCounter()

    var debouncer = Debouncer(window: 0.5, scheduler: scheduler, now: { clock.date() })

    debouncer.trigger { probe.record(1) }
    clock.advance(by: 0.2)
    debouncer.trigger { probe.record(2) }
    clock.advance(by: 0.2)
    debouncer.trigger { probe.record(3) }

    XCTAssertEqual(
      scheduler.pendingCount, 1,
      "a burst inside one window must collapse to a single scheduled scan")
    XCTAssertEqual(
      scheduler.firstDeadline, epoch.addingTimeInterval(0.9),
      "the single firing is scheduled from the last trigger of the burst")

    scheduler.runPending()

    XCTAssertEqual(
      probe.recordedIDs, [3],
      "exactly one piece of work runs and it is the burst's latest")
  }

  func testTriggerAfterWindowClosesSchedulesAnotherFire() {
    let scheduler = WatchManualScheduler()
    let clock = WatchVirtualClock(epoch)
    let probe = WorkCounter()

    var debouncer = Debouncer(window: 0.5, scheduler: scheduler, now: { clock.date() })

    debouncer.trigger { probe.record(1) }
    scheduler.runPending()
    XCTAssertEqual(probe.recordedIDs, [1], "the first window fires its own work")
    XCTAssertEqual(scheduler.pendingCount, 0, "nothing stays pending after firing")

    clock.advance(by: 2.0)
    debouncer.trigger { probe.record(2) }

    XCTAssertEqual(
      scheduler.pendingCount, 1,
      "a trigger arriving after the previous window closed schedules a fresh fire")
    XCTAssertEqual(
      scheduler.firstDeadline, epoch.addingTimeInterval(2.5),
      "the fresh fire is measured from the new trigger")

    scheduler.runPending()
    XCTAssertEqual(
      probe.recordedIDs, [1, 2], "the second window fires its own work exactly once")
  }
}
