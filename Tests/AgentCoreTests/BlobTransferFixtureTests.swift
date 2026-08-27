import AgentCore
import Foundation
import XCTest

final class BlobTransferFixtureTests: XCTestCase {
  func testMultiChunkSessionFixtureHasDigestFirstShape() throws {
    let fixtureURL = URL(filePath: #filePath)
      .deletingLastPathComponent()
      .appending(path: "Fixtures/BlobTransfer/upload-session-request-multi-chunk.json")

    let data = try Data(contentsOf: fixtureURL)
    let declaration = try JSONDecoder().decode(BlobUploadDeclaration.self, from: data)

    XCTAssertEqual(declaration.declaredSizeBytes, 200_000)
    XCTAssertEqual(declaration.chunkSizeBytes, 1_048_576)
    XCTAssertEqual(declaration.digest.algorithm, "sha256")
    XCTAssertEqual(declaration.digest.hex.count, 64)
  }
}
