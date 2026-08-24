import AppKit
import XCTest

@testable import RatatoskrExportAgent

final class LaunchBehaviorTests: XCTestCase {
  private var smokeBinaryURL: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(".build/debug/RatatoskrExportAgent")
  }

  @MainActor
  func testAccessoryPresentationIsApplied() {
    applyBootstrapPresentation()

    XCTAssertEqual(
      NSApplication.shared.activationPolicy(),
      .accessory,
      "bootstrap presentation must leave the accessory activation policy applied"
    )
  }

  func testSmokeLaunchExitsZeroWithinBound() throws {
    let smokeProcess = Process()
    smokeProcess.executableURL = smokeBinaryURL
    smokeProcess.arguments = ["--smoke"]

    try smokeProcess.run()

    Thread.sleep(forTimeInterval: 0.05)
    XCTAssertTrue(
      smokeProcess.isRunning,
      "smoke launch must still be running shortly after start instead of exiting immediately"
    )

    let deadline = Date().addingTimeInterval(15)
    while smokeProcess.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }

    XCTAssertFalse(
      smokeProcess.isRunning, "smoke launch must terminate within the bounded interval")
    XCTAssertEqual(smokeProcess.terminationStatus, 0, "smoke launch must exit successfully")
  }

  func testUnknownArgumentPrintsUsageAndExitsNonZero() throws {
    let errorPipe = Pipe()

    let unknownFlagProcess = Process()
    unknownFlagProcess.executableURL = smokeBinaryURL
    unknownFlagProcess.arguments = ["--definitely-not-a-flag"]
    unknownFlagProcess.standardError = errorPipe

    try unknownFlagProcess.run()

    let deadline = Date().addingTimeInterval(10)
    while unknownFlagProcess.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.05)
    }

    if unknownFlagProcess.isRunning {
      unknownFlagProcess.terminate()
      unknownFlagProcess.waitUntilExit()
      XCTFail("unknown-argument launch must exit within the bounded interval instead of running on")
      return
    }

    let standardErrorText =
      String(
        bytes: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""

    XCTAssertNotEqual(
      unknownFlagProcess.terminationStatus,
      0,
      "unknown-argument launch must not report success"
    )
    XCTAssertTrue(
      standardErrorText.lowercased().contains("usage"),
      "unknown-argument launch must print usage text on standard error"
    )
  }
}
