import AgentCore
import XCTest

final class CandidateEligibilityTests: XCTestCase {
  func testOversizedFileIsRejectedImmediatelyWithLimit() {
    let gate = CandidateEligibilityGate(maxArchiveBytes: 100)

    let rejection = gate.rejection(isRegularFile: true, isReadable: true, byteSize: 101)

    XCTAssertEqual(
      rejection, .exceedsSizeLimit(limitBytes: 100),
      "a snapshot above the ceiling must be rejected naming the limit without waiting")
  }

  func testNonRegularFileIsRejectedNamingReason() {
    let gate = CandidateEligibilityGate(maxArchiveBytes: 100)

    let rejection = gate.rejection(isRegularFile: false, isReadable: true, byteSize: 10)

    XCTAssertEqual(
      rejection, .notRegularFile, "symlinks, directories and special files are refused")
  }

  func testUnreadableFileIsRejectedNamingReason() {
    let gate = CandidateEligibilityGate(maxArchiveBytes: 100)

    let rejection = gate.rejection(isRegularFile: true, isReadable: false, byteSize: 10)

    XCTAssertEqual(rejection, .unreadable, "an unreadable file must be rejected, never queued")
  }

  func testEligibleRegularFileAdmits() {
    let gate = CandidateEligibilityGate(maxArchiveBytes: 100)

    let rejection = gate.rejection(isRegularFile: true, isReadable: true, byteSize: 99)

    XCTAssertNil(rejection, "a readable regular file within the ceiling is eligible")
  }
}
