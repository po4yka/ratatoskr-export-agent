import AgentCore
import Foundation
import XCTest

final class ProductRuntimeVerticalFlowTests: XCTestCase {
  func testTwoProvidersReachPrivateTerminalHistoryWithDurableControls() async throws {
    let harness = try VerticalRuntimeHarness()

    let result = try await harness.run()

    XCTAssertEqual(result.entries.count, 3)
    XCTAssertEqual(result.entries.filter { $0.state == .confirmed }.count, 2)
    XCTAssertEqual(result.completed.map(\.routing.provider.rawValue).sorted(), ["chatgpt", "claude"])
    XCTAssertTrue(result.completed.allSatisfy { $0.backendImport?.presentation == .importedComplete })
    XCTAssertTrue(result.completed.allSatisfy { $0.backendImport?.terminalNoticeDelivered == true })
    XCTAssertEqual(result.cancelled.uploadCheckpoint?.control, .cancelled)
    XCTAssertEqual(result.duplicateID, result.completed.first { $0.routing.provider == .chatgpt }?.id)
    XCTAssertEqual(result.prepareCounts, ["chatgpt": 1, "claude": 1])
    XCTAssertGreaterThan(result.claudeStatusCount, 0)
    XCTAssertTrue(result.sources.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    XCTAssertTrue(result.completed.allSatisfy { entry in
      entry.managedArchivePath.map(FileManager.default.fileExists(atPath:)) == true
    })
    XCTAssertEqual(result.notices.count, 2)
    XCTAssertTrue(result.notices.allSatisfy { $0 == AgentNotification(presentation: .importedComplete) })
    XCTAssertFalse(result.journalText.contains("chatgpt-export.zip"))
    XCTAssertFalse(result.journalText.contains("claude-export.zip"))
    XCTAssertFalse(result.journalText.contains("credential-canary"))
  }
}

private final class VerticalRuntimeHarness {
  private let root: URL
  private let folderID = UUID()
  private let journal: LocalArchiveJournal
  private let processor: ArchiveCandidateProcessor
  private let transport = VerticalOperationTransport()
  private let notifications = VerticalNotificationService()
  private let chatGPT: URL
  private let claude: URL
  private let cancelled: URL

  init() throws {
    root = FileManager.default.temporaryDirectory.appending(path: "vertical-runtime-\(UUID())")
    let inbox = root.appending(path: "inbox")
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    chatGPT = try Self.writeArchive(
      named: "chatgpt-export.zip", entries: ["conversations.json", "user.json"], into: inbox
    )
    claude = try Self.writeArchive(
      named: "claude-export.zip", entries: ["conversations.json", "users.json"], into: inbox
    )
    cancelled = try Self.writeArchive(
      named: "cancelled-export.zip", entries: ["conversations.json", "user.json", "models.json"], into: inbox
    )
    journal = try LocalArchiveJournal.open(at: root.appending(path: "journal.jsonl"))
    processor = ArchiveCandidateProcessor(
      store: LocalArchiveStore(root: root.appending(path: "archives"), maxStoreBytes: 5_000_000),
      journal: journal,
      policies: [folderID: .preserveInPlace]
    )
  }

  func run() async throws -> VerticalResult {
    _ = try await processor.process(candidate(chatGPT))
    let claudeEntry = try await processor.process(candidate(claude))
    let duplicate = try await processor.process(candidate(chatGPT))
    let cancelledEntry = try await processor.process(candidate(cancelled))
    let queue = UploadQueue(
      journal: journal, operationTransport: transport, configuration: .defaultValue,
      retryPolicy: UploadRetryPolicy(initialDelay: 1, maximumDelay: 1)
    )
    let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    try await queue.pause(entryID: claudeEntry.id, now: epoch)
    try await queue.cancel(entryID: cancelledEntry.id, now: epoch)
    _ = await queue.runEligible(now: epoch)
    try await queue.retryNow(entryID: claudeEntry.id, now: epoch)
    _ = await queue.runEligible(now: epoch)
    _ = await queue.runEligible(now: epoch.addingTimeInterval(2))
    try await completeTerminalRuntime(queue: queue)
    return try await result(
      duplicateID: duplicate.id, cancelledID: cancelledEntry.id
    )
  }

  private func completeTerminalRuntime(queue: UploadQueue) async throws {
    let providers = Dictionary(uniqueKeysWithValues: await queue.entries().compactMap { entry in
      entry.operationID.map { ($0, entry.routing.provider) }
    })
    let backend = BackendImportRuntimeComponent(
      journal: journal,
      poller: BackendImportPollCoordinator(journal: journal, polling: VerticalOperationPoller(providers: providers)),
      notifications: ImportNotificationCoordinator(journal: journal, service: notifications)
    )
    let runtime = OperationalAgentRuntime(components: [backend])
    await runtime.start()
    await runtime.stop()
  }

  private func result(
    duplicateID: UUID,
    cancelledID: UUID
  ) async throws -> VerticalResult {
    let reopened = try LocalArchiveJournal.open(at: root.appending(path: "journal.jsonl"))
    let entries = reopened.entries
    let counts = await transport.prepareCounts
    let statusCount = await transport.claudeStatusCount
    let delivered = await notifications.delivered
    return VerticalResult(
      entries: entries,
      completed: entries.filter { $0.backendImport?.presentation.isTerminal == true },
      cancelled: try XCTUnwrap(entries.first { $0.id == cancelledID }),
      duplicateID: duplicateID,
      prepareCounts: counts,
      claudeStatusCount: statusCount,
      sources: [chatGPT, claude, cancelled],
      notices: delivered,
      journalText: try String(contentsOf: root.appending(path: "journal.jsonl"), encoding: .utf8)
    )
  }

  private func candidate(_ url: URL) -> StableArchiveCandidate {
    let size = (try? Data(contentsOf: url).count) ?? 0
    let snapshot = FileSnapshot(byteSize: size, modifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
    return StableArchiveCandidate(
      folderID: folderID, url: url, snapshot: snapshot,
      evidence: StabilityEvidence(quietDuration: 30, snapshot: snapshot)
    )
  }

  private static func writeArchive(named: String, entries: [String], into directory: URL) throws -> URL {
    try writeClassifierFixture(
      named: named,
      bytes: makeZipData(entries: entries.map { ZipFixtureEntry(name: $0) }),
      into: directory
    )
  }
}

private struct VerticalResult {
  let entries: [JournalEntry]
  let completed: [JournalEntry]
  let cancelled: JournalEntry
  let duplicateID: UUID
  let prepareCounts: [String: Int]
  let claudeStatusCount: Int
  let sources: [URL]
  let notices: [AgentNotification]
  let journalText: String
}
