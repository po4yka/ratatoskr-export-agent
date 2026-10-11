import CryptoKit
import Foundation
import XCTest
@testable import AgentCore

/// A 403 on the archive routes (for example `chatgpt.account.unmapped` relayed at finalize) is permanent:
/// XR-021 CONTRACTS.md section R3-03 rule 4, the same shape as the 413 rule of `PlatformArchiveTooLargeTests`.
final class PlatformArchiveRefusedTests: XCTestCase {
  private static let envelope = Data(
    #"{"code":"chatgpt.account.unmapped","message":"This user is not set up for archive import.","retryable":false}"#.utf8
  )

  override func tearDown() {
    ResumableURLProtocol.interceptor = nil
    ResumableURLProtocol.recorder = nil
    super.tearDown()
  }

  func testFinalizeForbiddenStopsAutomaticRetry() async throws {
    let scenario = try makeScenario { request in
      request.httpMethod == "POST" && request.url?.path.hasSuffix("/finalize") == true
    }
    try await assertPermanentFailure(scenario)
    XCTAssertTrue(scenario.log.requests.contains { $0.hasSuffix("/finalize") })
  }

  func testPrepareForbiddenStopsAutomaticRetry() async throws {
    let scenario = try makeScenario { request in
      request.httpMethod == "POST" && request.url?.path == "/v1/ai-archives/chatgpt"
    }
    try await assertPermanentFailure(scenario)
  }

  private func assertPermanentFailure(_ scenario: RefusedScenario) async throws {
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

  private func makeScenario(refusing matches: @escaping (URLRequest) -> Bool) throws -> RefusedScenario {
    let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
    let fingerprint = ArchiveFingerprint(
      sha256Hex: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      byteSize: bytes.count
    )
    let journal = try queuedJournal(bytes: bytes, fingerprint: fingerprint)
    let log = RefusedRequestLog()
    ResumableURLProtocol.recorder = ResumableRequestRecorder(fingerprint: fingerprint)
    ResumableURLProtocol.interceptor = { request in
      log.append("\(request.httpMethod ?? "") \(request.url?.path ?? "")")
      if matches(request) { return (403, Self.envelope) }
      // The shared recorder interrupts chunk 1 once; accept every chunk so the run reaches finalize.
      return request.httpMethod == "PUT" ? (204, Data()) : nil
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResumableURLProtocol.self]
    let transport = PlatformArchiveHTTPTransport(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: RefusedFixtureAuthorizer(),
      session: URLSession(configuration: configuration)
    )
    let queue = UploadQueue(
      journal: journal,
      operationTransport: transport,
      configuration: .defaultValue,
      retryPolicy: UploadRetryPolicy(initialDelay: 1, maximumDelay: 1)
    )
    return RefusedScenario(queue: queue, log: log)
  }

  private func queuedJournal(bytes: Data, fingerprint: ArchiveFingerprint) throws -> LocalArchiveJournal {
    let archive = FileManager.default.temporaryDirectory.appending(path: "xr021-refused-\(UUID()).zip")
    try bytes.write(to: archive)
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "xr021-refused-\(UUID()).journal")
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

private struct RefusedScenario {
  let queue: UploadQueue
  let log: RefusedRequestLog
}

private final class RefusedRequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String] = []

  var requests: [String] { lock.withLock { entries } }

  func append(_ request: String) { lock.withLock { entries.append(request) } }
}

private struct RefusedFixtureAuthorizer: PlatformRequestAuthorizing {
  func credentialForRequest() async throws -> String { "fixture-access" }
  func recoverCredential(afterRejectedCredential _: String) async throws -> String {
    "fixture-recovered-access"
  }
  func authorizationWasRejected(_: String) async {}
}
