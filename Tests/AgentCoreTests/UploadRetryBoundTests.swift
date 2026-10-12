import Foundation
import XCTest
@testable import AgentCore

/// XR-021 CONTRACTS.md section R5-05 rule 3: consecutive retryable failures are bounded.
final class UploadRetryBoundTests: XCTestCase {
  override func tearDown() {
    PlatformArchiveScenario.reset()
    super.tearDown()
  }

  func testThe25thConsecutiveRetryableFailureFailsTheEntry() async throws {
    let scenario = try PlatformArchiveScenario.make()
    scenario.server.override { $0.httpMethod == "POST" ? (503, Data()) : nil }

    for attempt in 1...24 {
      await scenario.run(at: TimeInterval(attempt * 10))
      let checkpoint = try await scenario.checkpoint()
      XCTAssertEqual(checkpoint.control, .active, "failure \(attempt)")
      XCTAssertEqual(checkpoint.attemptCount, attempt)
      XCTAssertNil(checkpoint.failureReason)
    }
    await scenario.run(at: 250)
    let exhausted = try await scenario.checkpoint()
    XCTAssertEqual(exhausted.control, .failed)
    XCTAssertEqual(exhausted.failureReason, .retriesExhausted)
    XCTAssertNil(exhausted.nextRetryAt)

    let requests = scenario.server.log.count
    await scenario.run(at: 1_000_000)
    XCTAssertEqual(scenario.server.log.count, requests)
  }

  func testTheBoundComesFromTheRetryPolicy() async throws {
    let scenario = try PlatformArchiveScenario.make(
      retryPolicy: UploadRetryPolicy(initialDelay: 1, maximumDelay: 1, maximumAttempts: 2)
    )
    scenario.server.override { $0.httpMethod == "POST" ? (503, Data()) : nil }
    for attempt in 1...3 { await scenario.run(at: TimeInterval(attempt * 10)) }
    let checkpoint = try await scenario.checkpoint()
    XCTAssertEqual(checkpoint.control, .failed)
    XCTAssertEqual(checkpoint.failureReason, .retriesExhausted)
  }

  func testRetryAfterFailuresCountAndCapacityDeferralsDoNot() async throws {
    let scenario = try PlatformArchiveScenario.make()
    let now = Date(timeIntervalSince1970: 100)
    let atTheBound = UploadCheckpoint(chunkSizeBytes: 65536, attemptCount: 24)

    let deferred = await scenario.queue.retryCheckpoint(
      for: BlobReceiptTransportError.capacityUnavailable, from: atTheBound, at: now
    )
    XCTAssertEqual(deferred.control, .active)
    XCTAssertEqual(deferred.attemptCount, 24)
    XCTAssertEqual(deferred.nextRetryAt, now)
    XCTAssertNil(deferred.failureReason)

    let throttled = await scenario.queue.retryCheckpoint(
      for: BlobReceiptTransportError.retryAfter(30), from: atTheBound, at: now
    )
    XCTAssertEqual(throttled.control, .failed)
    XCTAssertEqual(throttled.failureReason, .retriesExhausted)
  }

  func testAnAcknowledgedChunkResetsTheCount() async throws {
    let bytes = Data(repeating: 7, count: 30)
    let (journal, entry) = try queuedEntry(bytes: bytes)
    let queue = UploadQueue(
      journal: journal,
      transport: OneChunkPerRunTransport(),
      retryPolicy: UploadRetryPolicy(initialDelay: 1, maximumDelay: 1),
      limiter: UploadAdmissionLimiter(maximumActive: 2, bytesPerTick: 1000),
      chunkSize: 1
    )
    for run in 1...27 { _ = await queue.runEligible(now: Date(timeIntervalSince1970: TimeInterval(run * 10))) }

    let checkpoint = try XCTUnwrap(journal.entries.first { $0.id == entry.id }?.uploadCheckpoint)
    XCTAssertEqual(checkpoint.control, .active)
    XCTAssertEqual(checkpoint.attemptCount, 1)
    XCTAssertEqual(checkpoint.acknowledgedIndices.count, 27)
  }

  private func queuedEntry(bytes: Data) throws -> (LocalArchiveJournal, JournalEntry) {
    let archive = FileManager.default.temporaryDirectory.appending(path: "xr021-bound-\(UUID()).zip")
    try bytes.write(to: archive)
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "xr021-bound-\(UUID()).journal")
    )
    var entry = try journal.discover(
      fingerprint: ArchiveFingerprint(sha256Hex: digest(bytes), byteSize: bytes.count),
      routing: fixtureRouting(), managedArchiveURL: archive
    )
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    return (journal, entry)
  }
}

/// Takes one chunk per run, then fails the next with a retryable error: every run makes progress and then fails.
private actor OneChunkPerRunTransport: BlobReceiptTransport {
  private var received = Set<Int>()
  private var sentThisRun = 0

  func open(_ declaration: BlobUploadDeclaration, idempotencyKey _: String) async throws -> BlobUploadSession {
    BlobUploadSession(token: "bound-session", chunkSizeBytes: declaration.chunkSizeBytes)
  }

  func status(token _: String) async throws -> BlobUploadStatus {
    sentThisRun = 0
    return BlobUploadStatus(receivedIndices: received)
  }

  func send(token _: String, index: Int, bytes _: Data) async throws {
    guard sentThisRun == 0 else { throw BlobReceiptTransportError.unavailable }
    sentThisRun += 1
    received.insert(index)
  }

  func finalize(token _: String) async throws -> BlobStoredReceipt {
    throw BlobReceiptTransportError.unavailable
  }
}
