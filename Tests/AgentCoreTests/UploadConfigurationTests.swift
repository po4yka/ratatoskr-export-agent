import AgentCore
import Foundation
import XCTest

final class UploadConfigurationTests: XCTestCase {
  func testTransferCapsAreRequiredAndValidated() throws {
    XCTAssertNoThrow(try AgentConfiguration.load(from: write(
      "{\"schemaVersion\":1,\"maxArchiveBytes\":1000,\"maxConcurrentUploads\":1,\"uploadChunkBytes\":65536,\"maxUploadBytesPerSecond\":1048576}"
    )))
    for (field, caps) in [
      ("uploadChunkBytes", "\"uploadChunkBytes\":0,\"maxUploadBytesPerSecond\":1048576"),
      ("maxUploadBytesPerSecond", "\"uploadChunkBytes\":65536,\"maxUploadBytesPerSecond\":0"),
    ] {
      XCTAssertThrowsError(try AgentConfiguration.load(from: write(
        "{\"schemaVersion\":1,\"maxArchiveBytes\":1000,\"maxConcurrentUploads\":1,\(caps)}"
      ))) { XCTAssertTrue(String(describing: $0).contains(field)) }
    }
  }

  func testBandwidthCapMustAdmitOneConfiguredChunk() throws {
    XCTAssertThrowsError(try AgentConfiguration.load(from: write(
      "{\"schemaVersion\":1,\"maxArchiveBytes\":1000,\"maxConcurrentUploads\":1,\"uploadChunkBytes\":65536,\"maxUploadBytesPerSecond\":1}"
    ))) { XCTAssertTrue(String(describing: $0).contains("maxUploadBytesPerSecond")) }
  }

  private func write(_ json: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "upload-config-\(UUID().uuidString)")
    try Data(json.utf8).write(to: url)
    return url
  }
}
