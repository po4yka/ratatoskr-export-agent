@testable import AgentCore
import Foundation
import XCTest

/// Only Platform's own `401` (`platform.auth.unauthenticated`) costs the device pairing: XR-021 CONTRACTS.md section R3-03 rule 4.
final class PlatformUnauthenticatedVerdictTests: XCTestCase {
  func testA401WithoutThePlatformEnvelopeDoesNotRemoveThePairing() async throws {
    let outcome = try await answerEveryRequest(
      status: 401, body: #"{"code":"claude.auth.unauthenticated","message":"Authentication is required.","retryable":false}"#
    )
    outcome.assertPairingKept()
  }

  func testA401WithAnEmptyBodyDoesNotRemoveThePairing() async throws {
    let outcome = try await answerEveryRequest(status: 401, body: "")
    outcome.assertPairingKept()
  }

  func testA401WithTheMalformedBodyDoesNotRemoveThePairing() async throws {
    let outcome = try await answerEveryRequest(status: 401, body: "<html>not an envelope</html>")
    outcome.assertPairingKept()
  }

  func testA401WithPlatformAuthUnauthenticatedStillRemovesThePairingAfterOneRefresh() async throws {
    let outcome = try await answerEveryRequest(
      status: 401, body: #"{"code":"platform.auth.unauthenticated","message":"Authentication is required.","retryable":false}"#
    )
    XCTAssertEqual(outcome.requestCount, 2)
    XCTAssertEqual(outcome.refreshCount, 1)
    XCTAssertEqual(outcome.status, .rePairingRequired(outcome.identity))
    XCTAssertNil(outcome.storedCredentials)
    XCTAssertTrue(outcome.error is PlatformDeviceTransportError)
  }

  func testOperationPollAlsoKeepsThePairingOnANonPlatform401() async throws {
    let poller = try await makeHarness(status: 401, body: #"{"code":"chatgpt.auth.unauthenticated"}"#)
    let operationPoller = URLSessionBackendOperationPoller(
      origin: Self.origin, authorizer: poller.coordinator, session: poller.session
    )
    var thrown: Error?
    do { _ = try await operationPoller.fetchOperation(UUID()) } catch { thrown = error }
    let status = await poller.coordinator.status
    if case .unavailable? = thrown as? PlatformDeviceTransportError {} else {
      XCTFail("expected unavailable, got \(String(describing: thrown))")
    }
    XCTAssertEqual(status, .paired(poller.identity))
  }

  private static let origin = URL(string: "https://ratatoskr.example")!

  private func answerEveryRequest(status: Int, body: String) async throws -> VerdictOutcome {
    let harness = try await makeHarness(status: status, body: body)
    let transport = PlatformArchiveHTTPTransport(
      origin: Self.origin, authorizer: harness.coordinator, session: harness.session
    )
    var thrown: Error?
    do {
      _ = try await transport.prepare(
        provider: .chatgpt,
        fingerprint: ArchiveFingerprint(sha256Hex: String(repeating: "a", count: 64), byteSize: 7),
        idempotencyKey: "stable-key"
      )
    } catch { thrown = error }
    return VerdictOutcome(
      identity: harness.identity,
      error: thrown,
      status: await harness.coordinator.status,
      storedCredentials: try await harness.store.load(for: harness.identity),
      requestCount: VerdictURLProtocol.requestCount,
      refreshCount: await harness.devices.refreshCount
    )
  }

  private func makeHarness(status: Int, body: String) async throws -> VerdictHarness {
    VerdictURLProtocol.answer = (status, Data(body.utf8))
    VerdictURLProtocol.requestCount = 0
    let identity = PairedDeviceIdentity(
      origin: Self.origin, deviceID: UUID(), userID: UUID(),
      credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let devices = RefreshingDeviceTransport(identity: identity)
    let store = InMemoryDeviceCredentialStore()
    let coordinator = DeviceSessionCoordinator(transport: devices, credentialStore: store)
    try await coordinator.pair(origin: Self.origin, code: "pairing-code", displayName: nil)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [VerdictURLProtocol.self]
    return VerdictHarness(
      identity: identity, devices: devices, store: store, coordinator: coordinator,
      session: URLSession(configuration: configuration)
    )
  }
}

private struct VerdictHarness {
  let identity: PairedDeviceIdentity
  let devices: RefreshingDeviceTransport
  let store: InMemoryDeviceCredentialStore
  let coordinator: DeviceSessionCoordinator
  let session: URLSession
}

private struct VerdictOutcome {
  let identity: PairedDeviceIdentity
  let error: Error?
  let status: DevicePairingStatus
  let storedCredentials: DeviceCredentialSet?
  let requestCount: Int
  let refreshCount: Int

  func assertPairingKept(line: UInt = #line) {
    if case .unavailable? = error as? PlatformDeviceTransportError {} else {
      XCTFail("expected unavailable, got \(String(describing: error))", line: line)
    }
    XCTAssertEqual(status, .paired(identity), line: line)
    XCTAssertNotNil(storedCredentials, line: line)
  }
}

private actor RefreshingDeviceTransport: PlatformDeviceTransport {
  private let identity: PairedDeviceIdentity
  private(set) var refreshCount = 0

  init(identity: PairedDeviceIdentity) { self.identity = identity }

  func pair(_ request: DevicePairingRequest) async throws -> DevicePairingResponse {
    DevicePairingResponse(
      identity: identity,
      credentials: DeviceCredentialSet(
        deviceSecret: "root-secret", accessCredential: "initial-access",
        refreshToken: "initial-refresh", refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_100)
      )
    )
  }

  func refresh(origin: URL, refreshToken: String) async throws -> DeviceSessionCredentials {
    refreshCount += 1
    return DeviceSessionCredentials(
      accessCredential: "replacement-access", credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_200),
      refreshToken: "replacement-refresh", refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_300)
    )
  }

  func openSession(origin: URL, deviceID: UUID, deviceSecret: String) async throws -> DeviceSessionCredentials {
    throw PlatformDeviceTransportError.unavailable
  }
}

private final class VerdictURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var answer: (Int, Data) = (500, Data())
  nonisolated(unsafe) static var requestCount = 0
  override static func canInit(with request: URLRequest) -> Bool { true }
  override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requestCount += 1
    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.answer.0, httpVersion: "HTTP/1.1", headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.answer.1)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
