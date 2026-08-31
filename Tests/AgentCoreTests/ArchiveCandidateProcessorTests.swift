import AgentCore
import Foundation
import XCTest

final class ArchiveCandidateProcessorTests: XCTestCase {
  func testChatGPTAndClaudeBecomeImmutableMixedProviderQueueEntries() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "candidate-product-\(UUID())")
    let inbox = root.appending(path: "inbox")
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let chatGPT = try writeClassifierFixture(
      named: "chatgpt.zip",
      bytes: makeZipData(entries: [ZipFixtureEntry(name: "conversations.json"), ZipFixtureEntry(name: "user.json")]),
      into: inbox
    )
    let claude = try writeClassifierFixture(
      named: "claude.zip",
      bytes: makeZipData(entries: [ZipFixtureEntry(name: "conversations.json"), ZipFixtureEntry(name: "users.json")]),
      into: inbox
    )
    let folderID = UUID()
    let journal = try LocalArchiveJournal.open(at: root.appending(path: "journal.jsonl"))
    let processor = ArchiveCandidateProcessor(
      store: LocalArchiveStore(root: root.appending(path: "archives"), maxStoreBytes: 1_000_000),
      journal: journal,
      policies: [folderID: .preserveInPlace]
    )

    let first = try await processor.process(candidate(chatGPT, folderID: folderID))
    let second = try await processor.process(candidate(claude, folderID: folderID))

    XCTAssertEqual([first.routing.provider, second.routing.provider], [.chatgpt, .claude])
    XCTAssertEqual([first.state, second.state], [.queued, .queued])
    XCTAssertTrue(try XCTUnwrap(first.managedArchivePath).contains("/archives/"))
    XCTAssertTrue(FileManager.default.fileExists(atPath: chatGPT.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: claude.path))
  }

  func testSocialArchiveIsNotPreservedOrRoutedAsAI() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "candidate-social-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let social = try writeClassifierFixture(
      named: "threads.zip",
      bytes: makeZipData(entries: [ZipFixtureEntry(name: "threads/posts.json")]),
      into: root
    )
    let folderID = UUID()
    let journal = try LocalArchiveJournal.open(at: root.appending(path: "journal.jsonl"))
    let processor = ArchiveCandidateProcessor(
      store: LocalArchiveStore(root: root.appending(path: "archives"), maxStoreBytes: 1_000_000),
      journal: journal,
      policies: [folderID: .archiveAfterUpload]
    )

    let stableCandidate = candidate(social, folderID: folderID)
    await XCTAssertThrowsErrorAsync { try await processor.process(stableCandidate) }

    let entries = await processor.entries()
    XCTAssertTrue(entries.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "archives").path))
  }

  private func candidate(_ url: URL, folderID: UUID) -> StableArchiveCandidate {
    let size = (try? Data(contentsOf: url).count) ?? 0
    return StableArchiveCandidate(
      folderID: folderID,
      url: url,
      snapshot: FileSnapshot(byteSize: size, modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)),
      evidence: StabilityEvidence(
        quietDuration: 30,
        snapshot: FileSnapshot(
          byteSize: size, modifiedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
      )
    )
  }
}
