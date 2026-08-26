import AgentCore
import XCTest

/// Store-budget decoding: documented default when absent, positive when
/// present.
final class ConfigurationStoreBudgetTests: XCTestCase {
  private func writeTemporaryConfiguration(_ json: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ratatoskr-config-\(UUID().uuidString).json")
    try Data(json.utf8).write(to: url)
    return url
  }

  func testMissingStoreBudgetDefaultsToDocumentedDefault() throws {
    let url = try writeTemporaryConfiguration(
      #"{"schemaVersion": 1, "maxArchiveBytes": 1000, "maxConcurrentUploads": 1}"#
    )

    let configuration = try AgentConfiguration.load(from: url)

    XCTAssertEqual(
      configuration.maxArchiveStoreBytes,
      AgentConfiguration.defaultValue.maxArchiveStoreBytes,
      "an omitted maxArchiveStoreBytes must fall back to the documented default")
  }

  func testNonPositiveStoreBudgetRejectedNamingField() throws {
    let url = try writeTemporaryConfiguration(
      #"{"schemaVersion": 1, "maxArchiveBytes": 1000, "maxConcurrentUploads": 1, "maxArchiveStoreBytes": 0}"#
    )

    XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains("maxArchiveStoreBytes"),
        "expected the error to name the offending budget field, got: \(error)"
      )
    }
  }
}
