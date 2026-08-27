import Foundation
import XCTest

@testable import AgentCore

final class ApplicationUpdatePolicyTests: XCTestCase {
  func testManualUpdateDiagnosticsDecodesExactCurrentVersion() throws {
    let data = Data(#"{"manualDownload":{"currentVersion":"1.2.3"}}"#.utf8)

    let value = try JSONDecoder().decode(UpdateCheckDiagnostics.self, from: data)

    XCTAssertEqual(
      String(describing: value),
      #"manualDownload(currentVersion: Optional("1.2.3"))"#
    )
  }

  func testManualUpdateDiagnosticsDecodesUnavailableVersionWithoutGuess() throws {
    let data = Data(#"{"manualDownload":{"currentVersion":null}}"#.utf8)

    let value = try JSONDecoder().decode(UpdateCheckDiagnostics.self, from: data)

    XCTAssertEqual(String(describing: value), "manualDownload(currentVersion: nil)")
  }
}
