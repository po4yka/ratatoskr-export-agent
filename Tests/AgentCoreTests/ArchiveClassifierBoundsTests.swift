import AgentCore
import XCTest

final class ArchiveClassifierBoundsTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
  }

  private func classify(named name: String, bytes: Data) throws -> ArchiveClassification {
    let file = try writeClassifierFixture(named: name, bytes: bytes, into: directory)
    return try ArchiveClassifier().classify(at: file)
  }

  func testMarkerlessZipIsUnidentifiedButStillZip() throws {
    let classification = try classify(
      named: "generic.zip",
      bytes: makeZipData(entries: [ZipFixtureEntry(name: "readme.txt")])
    )

    XCTAssertEqual(classification.container, .zip)
    XCTAssertEqual(
      classification.provider, .unidentified,
      "a zip with no provider markers stays unidentified rather than guessing")
    XCTAssertNil(
      classification.confidence,
      "no matched evidence must carry no confidence")
  }

  func testUnrecognizableBinaryClassifiesCleanly() throws {
    let classification = try classify(
      named: "blob.bin",
      bytes: Data([0x00, 0x01, 0x02, 0xFF, 0xFE])
    )

    XCTAssertEqual(classification.container, .unknown)
    XCTAssertEqual(classification.provider, .unidentified)
    XCTAssertNil(classification.confidence)
  }

  func testJSONConversationShapesLabelTheirProviders() throws {
    let chatgpt = try classify(
      named: "chats-chatgpt.json",
      bytes: Data("[{\"title\": \"t\", \"mapping\": {}, \"current_node\": \"n\"}]".utf8)
    )
    let claude = try classify(
      named: "chats-claude.json",
      bytes: Data("{\"uuid\": \"u\", \"name\": \"n\", \"chat_messages\": []}".utf8)
    )

    XCTAssertEqual(chatgpt.container, .json)
    XCTAssertEqual(
      chatgpt.provider, .chatgpt, "the chatgpt key row must label from structure alone")
    XCTAssertEqual(claude.container, .json)
    XCTAssertEqual(claude.provider, .claude, "the claude key row must label from structure alone")
  }

  func testDeepNestedContentIsNotRequiredForVerdicts() throws {
    let shallowKeysOnly = "{\"uuid\": null, \"chat_messages\": null}"

    let classification = try classify(named: "claude-shape.json", bytes: Data(shallowKeysOnly.utf8))

    XCTAssertEqual(
      classification.provider, .claude,
      "top-level keys alone must decide; nested levels are never parsed")
  }

  func testCentralDirectoryBeyondScanWindowStaysUnidentified() throws {
    let classification = try classify(
      named: "commented.zip",
      bytes: makeZipData(
        entries: [ZipFixtureEntry(name: "your_instagram_activity/likes.json")],
        comment: Data(repeating: 0x2D, count: 70_000)
      )
    )

    XCTAssertEqual(
      classification.container, .zip,
      "the magic-byte sniff still holds when the EOCD sits beyond the window")
    XCTAssertEqual(
      classification.provider, .unidentified,
      "an EOCD outside the bounded scan window yields no marker verdict")
    XCTAssertNil(classification.confidence)
  }
}
