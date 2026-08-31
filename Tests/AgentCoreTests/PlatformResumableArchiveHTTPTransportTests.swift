import CryptoKit
import Foundation
import XCTest
@testable import AgentCore

final class PlatformResumableArchiveHTTPTransportTests: XCTestCase {
  func testInterruptionRelaunchResumesSameOperation() async throws {
    let scenario = try makeScenario()
    var journal = scenario.journal
    var queue = UploadQueue(
      journal: journal,
      operationTransport: makeTransport(recorder: scenario.recorder),
      configuration: .defaultValue,
      retryPolicy: UploadRetryPolicy(initialDelay: 1, maximumDelay: 1)
    )
    _ = await queue.runEligible(now: Date(timeIntervalSince1970: 100))

    journal = try LocalArchiveJournal.open(at: scenario.journalURL)
    queue = UploadQueue(
      journal: journal,
      operationTransport: makeTransport(recorder: scenario.recorder),
      configuration: .defaultValue,
      retryPolicy: UploadRetryPolicy(initialDelay: 1, maximumDelay: 1)
    )
    _ = await queue.runEligible(now: Date(timeIntervalSince1970: 102))

    try await assertCompleted(queue: queue, recorder: scenario.recorder)
  }

  private func makeScenario() throws -> ResumableScenario {
    let bytes = Data((0..<150_000).map { UInt8($0 % 251) })
    let archive = FileManager.default.temporaryDirectory.appending(
      path: "xpa020-http-\(UUID()).zip")
    try bytes.write(to: archive)
    let fingerprint = ArchiveFingerprint(
      sha256Hex: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
      byteSize: bytes.count
    )
    let journalURL = FileManager.default.temporaryDirectory.appending(
      path: "xpa020-http-\(UUID()).journal")
    let journal = try LocalArchiveJournal.open(at: journalURL)
    var entry = try journal.discover(
      fingerprint: fingerprint, routing: fixtureRouting(), managedArchiveURL: archive
    )
    for state in [JournalState.archived, .hashed, .queued] {
      entry = try journal.advance(entryID: entry.id, to: state)
    }
    let recorder = ResumableRequestRecorder(fingerprint: fingerprint)
    return ResumableScenario(journal: journal, journalURL: journalURL, recorder: recorder)
  }

  private func assertCompleted(
    queue: UploadQueue, recorder: ResumableRequestRecorder
  ) async throws {
    let requests = recorder.requests
    XCTAssertEqual(requests.filter { $0 == "POST /v1/ai-archives/chatgpt" }.count, 1)
    let transfer = "/v1/ai-archives/chatgpt/00000000-0000-0000-0000-000000000221/uploads"
    let token = "rst_000000000000000000000221"
    XCTAssertTrue(requests.contains("POST \(transfer)"))
    XCTAssertTrue(requests.contains("GET \(transfer)/\(token)/status"))
    XCTAssertTrue(requests.contains { $0.contains("/chunks/") })
    XCTAssertTrue(requests.contains("POST \(transfer)/\(token)/finalize"))
    XCTAssertEqual(recorder.finalizeBody, #"{"resumption_token":"rst_000000000000000000000221"}"#)
    let entries = await queue.entries()
    let finished = try XCTUnwrap(entries.first)
    XCTAssertEqual(
      finished.operationID?.uuidString.lowercased(), "00000000-0000-0000-0000-000000000221")
    XCTAssertEqual(finished.state, .uploaded)
  }

  private func makeTransport(recorder: ResumableRequestRecorder) -> PlatformArchiveHTTPTransport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ResumableURLProtocol.self]
    ResumableURLProtocol.recorder = recorder
    return PlatformArchiveHTTPTransport(
      origin: URL(string: "https://ratatoskr.example")!,
      authorizer: ConstantPlatformAuthorizer(),
      session: URLSession(configuration: configuration)
    )
  }
}

private struct ResumableScenario {
  let journal: LocalArchiveJournal
  let journalURL: URL
  let recorder: ResumableRequestRecorder
}

private struct ConstantPlatformAuthorizer: PlatformRequestAuthorizing {
  func credentialForRequest() async throws -> String { "fixture-access" }
  func recoverCredential(afterRejectedCredential _: String) async throws -> String {
    "fixture-recovered-access"
  }
  func authorizationWasRejected(_: String) async {}
}

final class ResumableRequestRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private let fingerprint: ArchiveFingerprint
  private var storedRequests: [String] = []
  private var received = Set<Int>()
  private var didInterrupt = false
  private var storedFinalizeBody: String?

  init(fingerprint: ArchiveFingerprint) { self.fingerprint = fingerprint }

  var requests: [String] { lock.withLock { storedRequests } }
  var finalizeBody: String? { lock.withLock { storedFinalizeBody } }

  func response(for request: URLRequest) -> (Int, Data) {
    lock.withLock {
      let path = request.url?.path ?? ""
      storedRequests.append("\(request.httpMethod ?? "") \(path)")
      if request.httpMethod == "POST", path == "/v1/ai-archives/chatgpt" {
        return (202, prepareResponse())
      }
      if request.httpMethod == "POST", path.hasSuffix("/uploads") {
        return (201, openResponse())
      }
      if request.httpMethod == "GET", path.hasSuffix("/rst_000000000000000000000221/status") {
        return (200, statusResponse())
      }
      if request.httpMethod == "PUT", let index = Int(path.split(separator: "/").last ?? "") {
        received.insert(index)
        if index == 1, !didInterrupt {
          didInterrupt = true
          return (503, Data())
        }
        return (204, Data())
      }
      if request.httpMethod == "POST", path.hasSuffix("/rst_000000000000000000000221/finalize") {
        storedFinalizeBody = requestBody(request).flatMap { String(data: $0, encoding: .utf8) }
        return (200, finalizeResponse())
      }
      return (204, Data())
    }
  }

  private func prepareResponse() -> Data {
    Data(
      #"{"operation_id":"00000000-0000-0000-0000-000000000221","status":"accepted"}"#.utf8
    )
  }

  private func openResponse() -> Data {
    Data(
      #"{"resumption_token":"rst_000000000000000000000221","chunk_size_bytes":65536,"expires_at":"2030-01-01T00:00:00Z"}"#.utf8
    )
  }

  private func statusResponse() -> Data {
    let indices = received.sorted().map(String.init).joined(separator: ",")
    let body = """
      {"resumption_token":"rst_000000000000000000000221","session_state":"open",\
      "received_chunks":[\(indices)],"received_chunks_count":\(received.count),\
      "missing_chunks_count":0}
      """
    return Data(body.utf8)
  }

  private func finalizeResponse() -> Data {
    let body = """
      {"outcome":"stored","blob_ref":{"owner_service":"platform",\
      "digest":{"algorithm":"sha256","hex":"\(fingerprint.sha256Hex)"},\
      "media_type":"application/zip","length_bytes":\(fingerprint.byteSize)}}
      """
    return Data(body.utf8)
  }

  private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
