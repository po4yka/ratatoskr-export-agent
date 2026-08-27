import AgentCore
import Foundation
import XCTest

final class ConfigurationDefaultsTests: XCTestCase {
  func testMissingFileYieldsDefaults() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString)")
    let configuration = try AgentConfiguration.load(from: url)
    XCTAssertNil(configuration.backendBaseURL)
    XCTAssertEqual(configuration.maxArchiveBytes, 2 * 1024 * 1024 * 1024)
    XCTAssertEqual(configuration.maxConcurrentUploads, 2)
  }
}
