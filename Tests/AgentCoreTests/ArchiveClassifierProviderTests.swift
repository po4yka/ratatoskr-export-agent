import AgentCore
import XCTest

final class ArchiveClassifierProviderTests: XCTestCase {
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

  private func classify(zip entries: [ZipFixtureEntry]) throws -> ArchiveClassification {
    let file = try writeClassifierFixture(
      named: "candidate.zip",
      bytes: makeZipData(entries: entries),
      into: directory
    )
    return try ArchiveClassifier().classify(at: file)
  }

  func testChatGPTMarkersLabelChatGPTStrongly() throws {
    let classification = try self.classify(zip: [
      ZipFixtureEntry(name: "conversations.json"),
      ZipFixtureEntry(name: "user.json"),
    ])

    XCTAssertEqual(classification.provider, .chatgpt, "the full chatgpt row must label chatgpt")
    XCTAssertEqual(classification.confidence, .strong)
    XCTAssertFalse(
      classification.matchedMarkers.isEmpty,
      "the matched marker names belong in the evidence")
  }

  func testClaudeMarkersLabelClaudeStrongly() throws {
    let classification = try self.classify(zip: [
      ZipFixtureEntry(name: "conversations.json", data: Data("[]".utf8)),
      ZipFixtureEntry(name: "users.json"),
    ])

    XCTAssertEqual(classification.provider, .claude, "the full claude row must label claude")
    XCTAssertEqual(classification.confidence, .strong)
  }

  func testInstagramActivityFolderLabelsInstagram() throws {
    let classification = try self.classify(zip: [
      ZipFixtureEntry(name: "your_instagram_activity/comments.json")
    ])

    XCTAssertEqual(
      classification.provider, .instagram,
      "an entry under the activity folder prefix must label instagram")
  }

  func testThreadsMarkersLabelThreads() throws {
    let classification = try self.classify(zip: [
      ZipFixtureEntry(name: "threads/inbox/thread_1.json")
    ])

    XCTAssertEqual(classification.provider, .threads, "the threads row must label threads")
  }

  func testOverlappingWeakEvidenceReportsAmbiguous() throws {
    let classification = try self.classify(zip: [
      ZipFixtureEntry(name: "conversations.json")
    ])

    XCTAssertEqual(
      classification.confidence, .ambiguous,
      "a bare conversations.json partially matches two rows and must not guess")
  }
}
