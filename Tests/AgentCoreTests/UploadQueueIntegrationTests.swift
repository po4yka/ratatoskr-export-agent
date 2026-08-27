import AgentCore
import CryptoKit
import Foundation
import XCTest

final class UploadQueueIntegrationTests: XCTestCase {
  func testInterruptedChunkIsCheckpointedThenResumedFromJournal() async throws {
    let bytes = Data((0 ..< 130_000).map { UInt8($0 % 251) })
    let archiveURL = try write(bytes)
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count)
    let journalURL = FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString)")
    let journal = try LocalArchiveJournal.open(at: journalURL)
    var entry = try journal.discover(fingerprint: fingerprint, managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let harness = QueueReceiptHarness(fingerprint: fingerprint, interruptAfterIndex: 1)
    let queue = UploadQueue(
      journal: journal,
      transport: harness,
      retryPolicy: UploadRetryPolicy(initialDelay: 5, maximumDelay: 60),
      limiter: UploadAdmissionLimiter(maximumActive: 1, bytesPerTick: 131_072),
      chunkSize: 65536
    )
    let now = Date(timeIntervalSince1970: 1000)

    _ = await queue.runEligible(now: now)

    let deferredEntries = await queue.entries()
    let deferred = try XCTUnwrap(deferredEntries.single)
    XCTAssertEqual(deferred.state, .queued)
    XCTAssertEqual(deferred.uploadCheckpoint?.resumptionToken, "queue-session")
    XCTAssertEqual(deferred.uploadCheckpoint?.acknowledgedIndices, [0])
    XCTAssertEqual(deferred.uploadCheckpoint?.nextRetryAt, now.addingTimeInterval(5))

    _ = await queue.runEligible(now: now.addingTimeInterval(5))

    let completedEntries = await queue.entries()
    XCTAssertEqual(completedEntries.single?.state, .uploaded)
    let sentIndices = await harness.sentIndices
    XCTAssertEqual(sentIndices, [0, 1])
  }

  func testBandwidthCapDefersUnreadChunksUntilNextSchedulerTick() async throws {
    let bytes = Data(repeating: 3, count: 130_000)
    let archiveURL = try write(bytes)
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count)
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "bandwidth-\(UUID().uuidString)")
    )
    var entry = try journal.discover(fingerprint: fingerprint, managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let harness = QueueReceiptHarness(fingerprint: fingerprint)
    let queue = UploadQueue(
      journal: journal,
      transport: harness,
      retryPolicy: UploadRetryPolicy(),
      limiter: UploadAdmissionLimiter(maximumActive: 1, bytesPerTick: 65536),
      chunkSize: 65536
    )
    let now = Date(timeIntervalSince1970: 2000)

    _ = await queue.runEligible(now: now)

    let deferredEntries = await queue.entries()
    let firstTickBytes = await harness.receivedByteCount
    XCTAssertEqual(deferredEntries.single?.state, .queued)
    XCTAssertEqual(firstTickBytes, 65536)

    _ = await queue.runEligible(now: now.addingTimeInterval(1))

    let completedEntries = await queue.entries()
    let receivedByteCount = await harness.receivedByteCount
    XCTAssertEqual(completedEntries.single?.state, .uploaded)
    XCTAssertEqual(receivedByteCount, bytes.count)
  }

  func testPermanentFailureStopsAutomaticRetryUntilExplicitRetry() async throws {
    let bytes = Data(repeating: 4, count: 1)
    let archiveURL = try write(bytes)
    let fingerprint = ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count)
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "permanent-\(UUID().uuidString)")
    )
    var entry = try journal.discover(fingerprint: fingerprint, managedArchiveURL: archiveURL)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let transport = PermanentFailureTransport()
    let queue = UploadQueue(
      journal: journal,
      transport: transport,
      retryPolicy: UploadRetryPolicy(),
      limiter: UploadAdmissionLimiter(maximumActive: 1, bytesPerTick: 65536),
      chunkSize: 65536
    )
    let now = Date(timeIntervalSince1970: 3000)

    _ = await queue.runEligible(now: now)
    _ = await queue.runEligible(now: now.addingTimeInterval(60))

    let failedEntries = await queue.entries()
    let failedEntry = failedEntries.single
    let initialOpenCount = await transport.openCount
    XCTAssertEqual(failedEntry?.uploadCheckpoint?.control, .failed)
    XCTAssertEqual(initialOpenCount, 1)

    try await queue.retryNow(entryID: entry.id, now: now.addingTimeInterval(61))
    _ = await queue.runEligible(now: now.addingTimeInterval(61))

    let retriedOpenCount = await transport.openCount
    XCTAssertEqual(retriedOpenCount, 2)
  }

  private func write(_ bytes: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "queue-archive-\(UUID().uuidString)")
    try bytes.write(to: url)
    return url
  }

  private func digest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

private actor QueueReceiptHarness: BlobReceiptTransport {
  let fingerprint: ArchiveFingerprint
  let interruptAfterIndex: Int?
  var didInterrupt = false
  var received = Set<Int>()
  var sentIndices = [Int]()

  init(fingerprint: ArchiveFingerprint, interruptAfterIndex: Int? = nil) {
    self.fingerprint = fingerprint
    self.interruptAfterIndex = interruptAfterIndex
  }

  func open(_ declaration: BlobUploadDeclaration, idempotencyKey _: String) async throws -> BlobUploadSession {
    BlobUploadSession(token: "queue-session", chunkSizeBytes: declaration.chunkSizeBytes)
  }

  func status(token: String) async throws -> BlobUploadStatus {
    guard token == "queue-session" else { throw BlobReceiptTransportError.expiredSession }
    return BlobUploadStatus(receivedIndices: received)
  }

  func send(token _: String, index: Int, bytes _: Data) async throws {
    received.insert(index)
    sentIndices.append(index)
    if index == interruptAfterIndex, !didInterrupt {
      didInterrupt = true
      throw BlobReceiptTransportError.unavailable
    }
  }

  func finalize(token _: String) async throws -> BlobStoredReceipt {
    BlobStoredReceipt(sha256Hex: fingerprint.sha256Hex, byteSize: fingerprint.byteSize, reference: "stored")
  }

  var receivedByteCount: Int {
    received.count == 0 ? 0 : received.reduce(0) { total, index in
      let remaining = fingerprint.byteSize - index * 65536
      return total + min(65536, remaining)
    }
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
