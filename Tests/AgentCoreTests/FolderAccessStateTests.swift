import AgentCore
import XCTest

final class FolderAccessStateTests: XCTestCase {
  func testCorruptBytesMapToNeedsReauthorization() {
    let state = FolderAccessClassifier.state(for: .bookmarkUnresolvable)

    XCTAssertEqual(
      state, .needsReauthorization,
      "unresolvable bookmark bytes must surface as needs-reauthorization")
  }

  func testStaleBookmarkMapsToNeedsReauthorization() {
    let state = FolderAccessClassifier.state(for: .resolvedStale)

    XCTAssertEqual(
      state, .needsReauthorization,
      "a stale bookmark over an existing target must surface as needs-reauthorization")
  }

  func testVanishedTargetMapsToMissing() {
    let state = FolderAccessClassifier.state(for: .targetVanished)

    XCTAssertEqual(
      state, .missing,
      "a resolvable bookmark whose target vanished must surface as missing")
  }

  func testPermissionFailureMapsToDenied() {
    let state = FolderAccessClassifier.state(for: .unreadableDueToPermissions)

    XCTAssertEqual(
      state, .denied,
      "a permission-refused folder must surface as denied")
  }
}
