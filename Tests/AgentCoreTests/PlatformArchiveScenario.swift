import CryptoKit
import Foundation
import XCTest
@testable import AgentCore

/// One queued archive of three 64 KiB chunks behind `PlatformArchiveHTTPTransport` and a `FakePlatformServer`.
struct PlatformArchiveScenario {
  let queue: UploadQueue
  let server: FakePlatformServer

  static func make(
    retryPolicy: UploadRetryPolicy = UploadRetryPolicy(initialDelay: 1, maximumDelay: 1),
    configuration: AgentConfiguration = .defaultValue
  ) throws -> PlatformArchiveScenario {
    let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
    let fingerprint = ArchiveFingerprint(
      sha256Hex: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      byteSize: bytes.count
    )
    let archive = FileManager.default.temporaryDirectory.appending(path: "xr021-scenario-\(UUID()).zip")
    try bytes.write(to: archive)
    let journal = try LocalArchiveJournal.open(
      at: FileManager.default.temporaryDirectory.appending(path: "xr021-scenario-\(UUID()).journal")
    )
    var entry = try journal.discover(fingerprint: fingerprint, routing: fixtureRouting(), managedArchiveURL: archive)
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let server = FakePlatformServer(fingerprint: fingerprint)
    ResumableURLProtocol.recorder = nil
    ResumableURLProtocol.interceptor = { server.answer($0) }
    let session = URLSessionConfiguration.ephemeral
    session.protocolClasses = [ResumableURLProtocol.self]
    let transport = PlatformArchiveHTTPTransport(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: ScenarioAuthorizer(),
      session: URLSession(configuration: session)
    )
    let queue = UploadQueue(
      journal: journal, operationTransport: transport, configuration: configuration, retryPolicy: retryPolicy
    )
    return PlatformArchiveScenario(queue: queue, server: server)
  }

  static func reset() {
    ResumableURLProtocol.interceptor = nil
    ResumableURLProtocol.recorder = nil
    ResumableURLProtocol.responseHeaders = nil
  }

  @discardableResult
  func run(at seconds: TimeInterval) async -> UploadQueueStatus {
    await queue.runEligible(now: Date(timeIntervalSince1970: seconds))
  }

  func entry() async throws -> JournalEntry {
    let entries = await queue.entries()
    return try XCTUnwrap(entries.first)
  }

  func checkpoint() async throws -> UploadCheckpoint {
    let entry = try await entry()
    return try XCTUnwrap(entry.uploadCheckpoint)
  }
}

struct ScenarioAuthorizer: PlatformRequestAuthorizing {
  func credentialForRequest() async throws -> String { "fixture-access" }
  func recoverCredential(afterRejectedCredential _: String) async throws -> String { "fixture-recovered-access" }
  func authorizationWasRejected(_: String) async {}
}
