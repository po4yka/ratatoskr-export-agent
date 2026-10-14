import AgentCore
import XCTest

final class VaultChangeBatchTests: XCTestCase {
  private let digest = String(repeating: "0f", count: 32)

  func testRenamedChangeHasPluginKeys() throws {
    let batch = VaultChangeBatch(
      changes: [
        VaultChange(sequence: 4, kind: .renamed, path: "Projects/Plan.md", previousPath: "Plan.md", sha256: digest, byteLength: 9),
      ]
    )

    let json = String(bytes: try batch.encoded(), encoding: .utf8)

    XCTAssertEqual(
      json,
      #"{"changes":[{"byte_length":9,"kind":"renamed","path":"Projects/Plan.md","previous_path":"Plan.md","#
        + #""sequence":4,"sha256":"\#(digest)"}]}"#
    )
  }

  func testDeletedChangeCarriesNoHash() throws {
    let batch = VaultChangeBatch(changes: [VaultChange(sequence: 1, kind: .deleted, path: "Old.md")])

    let json = String(bytes: try batch.encoded(), encoding: .utf8)

    XCTAssertEqual(json, #"{"changes":[{"kind":"deleted","path":"Old.md","sequence":1}]}"#)
  }

  func testSplitsAt256() {
    let changes = (1...257).map { VaultChange(sequence: UInt64($0), kind: .deleted, path: "\($0).md") }

    let batches = VaultChangeBatch.batches(of: changes)

    XCTAssertEqual(batches.map(\.changes.count), [256, 1])
    XCTAssertEqual(batches.last?.changes.first?.sequence, 257)
  }
}
