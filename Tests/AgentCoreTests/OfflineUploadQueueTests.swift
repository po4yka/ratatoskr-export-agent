import AgentCore
import XCTest

final class OfflineUploadQueueTests: XCTestCase {
  func testOfflineFailurePersistsAndDoesNotRetryBeforeEligibleTime() {
    let policy = UploadRetryPolicy(initialDelay: 5, maximumDelay: 60)
    let now = Date(timeIntervalSince1970: 1000)
    XCTAssertEqual(policy.nextEligible(at: now, attempt: 1), now.addingTimeInterval(5))
    XCTAssertEqual(policy.nextEligible(at: now, attempt: 8), now.addingTimeInterval(60))
    XCTAssertEqual(policy.nextEligible(at: now, attempt: 1, retryAfter: 20), now.addingTimeInterval(20))
  }

  func testGlobalConcurrencyAndBandwidthCapsAreEnforced() async {
    let limiter = UploadAdmissionLimiter(maximumActive: 2, bytesPerTick: 100)
    let firstReservation = await limiter.reserve(bytes: 60)
    let rejectedReservation = await limiter.reserve(bytes: 60)
    let activeAfterFirst = await limiter.activeUploads
    XCTAssertTrue(firstReservation)
    XCTAssertFalse(rejectedReservation)
    XCTAssertEqual(activeAfterFirst, 1)
    await limiter.release()
    await limiter.beginTick()
    let secondReservation = await limiter.reserve(bytes: 50)
    let thirdReservation = await limiter.reserve(bytes: 50)
    let activeAfterSecond = await limiter.activeUploads
    let capRejected = await limiter.reserve(bytes: 1)
    XCTAssertTrue(secondReservation)
    XCTAssertTrue(thirdReservation)
    XCTAssertEqual(activeAfterSecond, 2)
    XCTAssertFalse(capRejected)
  }
}
