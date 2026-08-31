import AgentCore
import XCTest

final class ConfigurationLoadingTests: XCTestCase {
  private func temporaryConfigurationURL() -> URL {
    let directory = FileManager.default.temporaryDirectory
    return directory.appendingPathComponent("ratatoskr-config-\(UUID().uuidString).json")
  }

  private func writeTemporaryConfiguration(_ json: String) throws -> URL {
    let url = temporaryConfigurationURL()
    var document = json
    if document.contains("\"schemaVersion\": 1"), !document.contains("\"uploadChunkBytes\"") {
      document = document.dropLast() + ", \"uploadChunkBytes\": 65536, \"maxUploadBytesPerSecond\": 1048576}"
    }
    try Data(document.utf8).write(to: url)
    return url
  }

  private func assertLoadFailsStatingOnlySchemaVersionOneIsSupported(for json: String) throws {
    let url = try writeTemporaryConfiguration(json)

    XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains("schema version 1"),
        "expected the error to state support for schema version 1 only, got: \(error)"
      )
    }
  }

  func testUnsupportedSchemaVersionFails() throws {
    try assertLoadFailsStatingOnlySchemaVersionOneIsSupported(for: #"{"schemaVersion": 2}"#)
  }

  func testMissingSchemaVersionFails() throws {
    try assertLoadFailsStatingOnlySchemaVersionOneIsSupported(for: "{}")
  }

  func testUnknownFieldIsRejectedAndNamed() throws {
    let url = try writeTemporaryConfiguration(
      #"{"schemaVersion": 1, "maxArchiveBytes": 1000, "maxConcurrentUploads": 1, "unexpected": true}"#
    )

    XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains("unexpected"),
        "expected the error to name the unknown field, got: \(error)"
      )
    }
  }

  func testWatchedFoldersFieldIsRejectedAsUnknown() throws {
    let url = try writeTemporaryConfiguration(
      #"{"schemaVersion": 1, "watchedFolders": [], "maxArchiveBytes": 1000, "maxConcurrentUploads": 1}"#
    )

    XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains("watchedFolders"),
        "expected the error to name the removed watchedFolders field, got: \(error)"
      )
    }
  }

  func testHttpsEndpointAccepted() throws {
    let url = try writeTemporaryConfiguration(
      #"{"schemaVersion": 1, "maxArchiveBytes": 1000, "maxConcurrentUploads": 1, "backendBaseURL": "https://ratatoskr.example"}"#
    )

    let configuration = try AgentConfiguration.load(from: url)

    XCTAssertEqual(configuration.backendBaseURL, URL(string: "https://ratatoskr.example"))
  }

  func testPlainHttpToPublicHostRejected() throws {
    let url = try writeTemporaryConfiguration(
      #"{"schemaVersion": 1, "maxArchiveBytes": 1000, "maxConcurrentUploads": 1, "backendBaseURL": "http://backup.example.com:8080"}"#
    )

    XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
      XCTAssertTrue(
        String(describing: error).contains("http://backup.example.com:8080"),
        "expected the error to identify the insecure endpoint, got: \(error)"
      )
    }
  }

  func testPlainHttpLoopbackRejectedInPersistedConfiguration() throws {
    for host in ["localhost", "127.0.0.1", "::1"] {
      let endpoint = host == "::1" ? "http://[::1]:8443" : "http://\(host):8443"
      let json =
        "{\"schemaVersion\": 1, \"maxArchiveBytes\": 1000, \"maxConcurrentUploads\": 1, \"backendBaseURL\": \"\(endpoint)\"}"
      let url = try writeTemporaryConfiguration(json)

      XCTAssertThrowsError(try AgentConfiguration.load(from: url))
    }
  }

  func testNonPositiveMaxArchiveBytesRejected() throws {
    for budget in [0, -1000] {
      let json =
        "{\"schemaVersion\": 1, \"maxArchiveBytes\": \(budget), \"maxConcurrentUploads\": 1}"
      let url = try writeTemporaryConfiguration(json)

      XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
        XCTAssertTrue(
          String(describing: error).contains("maxArchiveBytes"),
          "expected the error to name maxArchiveBytes for budget \(budget), got: \(error)"
        )
      }
    }
  }

  func testZeroMaxConcurrentUploadsRejected() throws {
    for concurrency in [0, -1] {
      let json =
        "{\"schemaVersion\": 1, \"maxArchiveBytes\": 1000, \"maxConcurrentUploads\": \(concurrency)}"
      let url = try writeTemporaryConfiguration(json)

      XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
        XCTAssertTrue(
          String(describing: error).contains("maxConcurrentUploads"),
          "expected the error to name maxConcurrentUploads for value \(concurrency), got: \(error)"
        )
      }
    }
  }

  func testValidationErrorNamesFileAndReasonWithoutContents() throws {
    let url = try writeTemporaryConfiguration(
      #"{"schemaVersion": 1, "maxArchiveBytes": 1000, "maxConcurrentUploads": 0}"#
    )

    XCTAssertThrowsError(try AgentConfiguration.load(from: url)) { error in
      let description = String(describing: error)
      XCTAssertTrue(
        description.contains(url.path),
        "expected the error to name the configuration file, got: \(description)"
      )
      XCTAssertTrue(
        description.contains("maxConcurrentUploads"),
        "expected the error to state the reason, got: \(description)"
      )
      XCTAssertFalse(
        description.contains("/Users/somebody/private/inbox"),
        "expected the error not to embed raw file contents, got: \(description)"
      )
    }
  }
}
