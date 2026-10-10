import CryptoKit
import Foundation
import XCTest
@testable import AgentCore

/// A Platform 413 `payload_too_large` refusal is permanent: XR-021 CONTRACTS.md section S06 D5.
final class PlatformArchiveTooLargeTests: XCTestCase {
  private static let envelope = Data(
    #"{"code":"payload_too_large","message":"The archive exceeds the size limit.","retryable":false}"#.utf8
  )

  override func tearDown() {
    ResumableURLProtocol.interceptor = nil
    ResumableURLProtocol.recorder = nil
    super.tearDown()
  }

  func testPrepareTooLargeStopsAutomaticRetry() async throws {
    let scenario = try makeScenario { request in
      request.httpMethod == "POST" && request.url?.path == "/v1/ai-archives/chatgpt"
    }
    try await assertPermanentFailure(scenario)
  }

  func testChunkTooLargeStopsAutomaticRetry() async throws {
    let scenario = try makeScenario { request in
      request.httpMethod == "PUT" && request.url?.path.contains("/chunks/") == true
    }
    try await assertPermanentFailure(scenario)
    XCTAssertTrue(scenario.log.requests.contains { $0.hasPrefix("PUT ") })
  }

  private func assertPermanentFailure(_ scenario: TooLargeScenario) async throws {
    let first = await scenario.queue.runEligible(now: Date(timeIntervalSince1970: 100))
    let entries = await scenario.queue.entries()
    let checkpoint = try XCTUnwrap(entries.first?.uploadCheckpoint)
    XCTAssertEqual(checkpoint.control, .failed)
    XCTAssertNil(checkpoint.nextRetryAt)
    XCTAssertEqual(first.failedCount, 1)
    XCTAssertEqual(first.menuTitle, "1 upload need attention")

    let requestsAfterFirstRun = scenario.log.requests.count
    _ = await scenario.queue.runEligible(now: Date(timeIntervalSince1970: 100_000))
    XCTAssertEqual(scenario.log.requests.count, requestsAfterFirstRun)
  }

  private func makeScenario(refusing matches: @escaping (URLRequest) -> Bool) throws -> TooLargeScenario {
    let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
    let fingerprint = ArchiveFingerprint(
      sha256Hex: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      byteSize: bytes.count
    )
    let journal = try queuedJournal(bytes: bytes, fingerprint: fingerprint)
    let recorder = ResumableRequestRecorder(fingerprint: fingerprint)
    let log = RequestLog()
    ResumableURLProtocol.recorder = recorder
    ResumableURLProtocol.interceptor = { request in
      log.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
      return matches(request) ? (413, Self.envelope) : nil
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResumableURLProtocol.self]
    let transport = PlatformArchiveHTTPTransport(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: FixtureAuthorizer(),
      session: URLSession(configuration: configuration)
    )
    let queue = UploadQueue(
      journal: journal,
      operationTransport: transport,
      configuration: .defaultValue,
      retryPolicy: UploadRetryPolicy(initialDelay: 1, maximumDelay: 1)
    )
    return TooLargeScenario(queue: queue, log: log)
  }

  private func queuedJournal(bytes: Data, fingerprint: ArchiveFingerprint) throws -> LocalArchiveJournal {
    let archive = FileManager.default.temporaryDirectory.appending(path: "xr021-too-large-\(UUID()).zip")
    try bytes.write(to: archive)
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "xr021-too-large-\(UUID()).journal")
    )
    var entry = try journal.discover(
      fingerprint: fingerprint, routing: fixtureRouting(), managedArchiveURL: archive
    )
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    return journal
  }
}

private struct TooLargeScenario {
  let queue: UploadQueue
  let log: RequestLog
}

private final class RequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String] = []

  var requests: [String] { lock.withLock { entries } }

  func append(_ request: String) { lock.withLock { entries.append(request) } }
}

private struct FixtureAuthorizer: PlatformRequestAuthorizing {
  func credentialForRequest() async throws -> String { "fixture-access" }
  func recoverCredential(afterRejectedCredential _: String) async throws -> String {
    "fixture-recovered-access"
  }
  func authorizationWasRejected(_: String) async {}
}
