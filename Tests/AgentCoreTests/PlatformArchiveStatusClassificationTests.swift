import Foundation
import XCTest
@testable import AgentCore

/// The answer table of XR-021 CONTRACTS.md section R5-05 rule 1, one row per route and status, driven through the real
/// `PlatformArchiveHTTPTransport` and `UploadQueue` against a `FakePlatformServer`.
final class PlatformArchiveStatusClassificationTests: XCTestCase {
  enum Route: String {
    case prepare, open, status, chunk, finalize

    func matches(_ request: URLRequest) -> Bool {
      let path = request.url?.path ?? ""
      let method = request.httpMethod ?? ""
      switch self {
      case .prepare: return method == "POST" && path == "/v1/ai-archives/chatgpt"
      case .open: return method == "POST" && path.hasSuffix("/uploads")
      case .status: return method == "GET" && path.hasSuffix("/status")
      case .chunk: return method == "PUT"
      case .finalize: return method == "POST" && path.hasSuffix("/finalize")
      }
    }
  }

  enum Outcome { case permanent, retryable, reopen }

  struct Row {
    let route: Route
    let status: Int
    let outcome: Outcome
    var retryable: Bool?
    var retryAfter: String?
    var envelopeCode: String?

    /// An `ErrorEnvelope` body when the row names a `retryable` flag or a code; otherwise an empty body.
    var body: Data {
      guard retryable != nil || envelopeCode != nil else { return Data() }
      let code = envelopeCode ?? "platform.test"
      return Data(#"{"code":"\#(code)","message":"fixture","retryable":\#(retryable ?? false)}"#.utf8)
    }
  }

  override func tearDown() {
    PlatformArchiveScenario.reset()
    super.tearDown()
  }

  func testPrepareAndOpenTable() async throws {
    for route in [Route.prepare, .open] {
      for status in [400, 422, 409] { try await check(Row(route: route, status: status, outcome: .permanent)) }
      for status in [404, 408, 429, 503] { try await check(Row(route: route, status: status, outcome: .retryable)) }
    }
  }

  func testStatusChunkAndFinalizeTable() async throws {
    for route in [Route.status, .chunk, .finalize] {
      try await check(Row(route: route, status: 404, outcome: .reopen))
      for status in [408, 429, 503] { try await check(Row(route: route, status: status, outcome: .retryable)) }
    }
    try await check(Row(route: .chunk, status: 400, outcome: .retryable, retryable: false))
    try await check(Row(route: .finalize, status: 400, outcome: .retryable, retryable: false))
    try await check(Row(route: .status, status: 400, outcome: .permanent, retryable: false))
  }

  func testAnUnlistedClientErrorIsPermanentOnEveryRoute() async throws {
    for route in [Route.prepare, .open, .status, .chunk, .finalize] {
      try await check(Row(route: route, status: 418, outcome: .permanent))
    }
  }

  /// R5-05 gives route rows precedence over the envelope, and the envelope precedence over the status class.
  func testTheEnvelopeDecidesWhenNoRouteRuleApplies() async throws {
    try await check(Row(route: .prepare, status: 418, outcome: .retryable, retryable: true))
    try await check(Row(route: .chunk, status: 418, outcome: .retryable, retryable: true))
    try await check(Row(route: .prepare, status: 503, outcome: .permanent, retryable: false))
    try await check(Row(route: .finalize, status: 503, outcome: .permanent, retryable: false))
    try await check(Row(route: .open, status: 429, outcome: .permanent, retryable: false))
    try await check(Row(route: .chunk, status: 404, outcome: .reopen, retryable: false))
    try await check(Row(route: .prepare, status: 400, outcome: .permanent, retryable: true))
  }

  func testRetryAfterIsHonouredOnEveryRoute() async throws {
    for route in [Route.prepare, .open, .status, .chunk, .finalize] {
      try await check(Row(route: route, status: 429, outcome: .retryable, retryAfter: "120"))
    }
    try await check(Row(route: .prepare, status: 503, outcome: .retryable, retryAfter: "300"))
  }

  func testPairingAndSizeAnswersKeepTheirMeaning() async throws {
    for route in [Route.prepare, .open, .status, .chunk, .finalize] {
      try await check(Row(route: route, status: 403, outcome: .permanent, retryable: false))
      try await check(Row(route: route, status: 413, outcome: .permanent, retryable: false))
      try await check(Row(route: route, status: 401, outcome: .permanent, envelopeCode: "platform.auth.unauthenticated"))
      try await check(Row(route: route, status: 401, outcome: .retryable, envelopeCode: "chatgpt.auth.unauthenticated"))
    }
  }

  private func check(_ row: Row, file: StaticString = #filePath, line: UInt = #line) async throws {
    PlatformArchiveScenario.reset()
    let scenario = try PlatformArchiveScenario.make()
    scenario.server.override { row.route.matches($0) ? (row.status, row.body) : nil }
    ResumableURLProtocol.responseHeaders = row.retryAfter.map { ["Retry-After": $0] }
    let now: TimeInterval = 100
    await scenario.run(at: now)
    let checkpoint = try await scenario.checkpoint()
    verify(row, checkpoint, now: now, file: file, line: line)
  }

  private func verify(_ row: Row, _ checkpoint: UploadCheckpoint, now: TimeInterval, file: StaticString, line: UInt) {
    let label = "\(row.route.rawValue) \(row.status) retryable=\(String(describing: row.retryable))"
    switch row.outcome {
    case .permanent:
      XCTAssertEqual(checkpoint.control, .failed, label, file: file, line: line)
      XCTAssertNil(checkpoint.nextRetryAt, label, file: file, line: line)
    case .retryable, .reopen:
      XCTAssertEqual(checkpoint.control, .active, label, file: file, line: line)
      XCTAssertEqual(checkpoint.attemptCount, 1, label, file: file, line: line)
      XCTAssertNotNil(checkpoint.nextRetryAt, label, file: file, line: line)
      let earliest = now + (row.retryAfter.flatMap(TimeInterval.init) ?? 0)
      XCTAssertGreaterThanOrEqual(checkpoint.nextRetryAt ?? .distantPast, Date(timeIntervalSince1970: earliest), label, file: file, line: line)
    }
    if row.outcome == .reopen {
      XCTAssertNil(checkpoint.resumptionToken, label, file: file, line: line)
      XCTAssertTrue(checkpoint.acknowledgedIndices.isEmpty, label, file: file, line: line)
    }
  }
}
