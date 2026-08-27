import AgentCore
import XCTest

final class DeviceSessionCoordinatorTests: XCTestCase {
  private let origin = URL(string: "https://ratatoskr.example")!
  private let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
  private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!

  func testRefreshAtomicallyReplacesBothSessionCredentials() async throws {
    let fixture = SessionTransportFixture(pairing: pairingResponse(), refresh: .success(rotated()))
    let coordinator = try await pairedCoordinator(transport: fixture)

    let credential = try await coordinator.refreshedAccessCredential()
    let refreshTokens = await fixture.refreshTokens

    XCTAssertEqual(credential, "replacement-access")
    XCTAssertEqual(refreshTokens, ["initial-refresh"])
  }

  func testConcurrentRefreshCallersSendOneRefreshToken() async throws {
    let fixture = SessionTransportFixture(pairing: pairingResponse(), refresh: .success(rotated()))
    let coordinator = try await pairedCoordinator(transport: fixture)

    async let first = coordinator.refreshedAccessCredential()
    await fixture.waitForRefreshToStart()
    async let second = coordinator.refreshedAccessCredential()
    _ = try await [first, second]

    let refreshTokens = await fixture.refreshTokens
    XCTAssertEqual(refreshTokens, ["initial-refresh"])
  }

  func testRefreshRefusalOpensOneReplacementSession() async throws {
    let fixture = SessionTransportFixture(
      pairing: pairingResponse(), refresh: .failure(PlatformDeviceTransportError.refused),
      session: .success(rotated())
    )
    let coordinator = try await pairedCoordinator(transport: fixture)

    let credential = try await coordinator.refreshedAccessCredential()
    let openedSessionCount = await fixture.openedSessionCount

    XCTAssertEqual(credential, "replacement-access")
    XCTAssertEqual(openedSessionCount, 1)
  }

  func testDoubleUnauthenticatedResponseClearsCredentialsAndRequiresRepairing() async throws {
    let fixture = SessionTransportFixture(
      pairing: pairingResponse(), refresh: .failure(PlatformDeviceTransportError.refused),
      session: .failure(PlatformDeviceTransportError.refused)
    )
    let (coordinator, store) = try await pairedCoordinatorWithStore(transport: fixture)

    await XCTAssertThrowsErrorAsync { try await coordinator.refreshedAccessCredential() }

    let status = await coordinator.status
    let credentials = try await store.load(for: pairingResponse().identity)
    XCTAssertEqual(status, .rePairingRequired(pairingResponse().identity))
    XCTAssertNil(credentials)
  }

  func testRePairingRequiredDoesNotRetryAuthenticatedTransport() async throws {
    let fixture = SessionTransportFixture(
      pairing: pairingResponse(), refresh: .failure(PlatformDeviceTransportError.refused),
      session: .failure(PlatformDeviceTransportError.refused)
    )
    let coordinator = try await pairedCoordinator(transport: fixture)

    await XCTAssertThrowsErrorAsync { try await coordinator.refreshedAccessCredential() }
    await XCTAssertThrowsErrorAsync { try await coordinator.refreshedAccessCredential() }

    let refreshCount = await fixture.refreshTokens.count
    XCTAssertEqual(refreshCount, 1)
  }

  func testRevocationStatusAndErrorContainNoFixtureSecrets() async throws {
    let fixture = SessionTransportFixture(
      pairing: pairingResponse(), refresh: .failure(PlatformDeviceTransportError.refused),
      session: .failure(PlatformDeviceTransportError.refused)
    )
    let coordinator = try await pairedCoordinator(transport: fixture)

    let error = await capturedError { try await coordinator.refreshedAccessCredential() }
    let status = await coordinator.status
    let output = "\(String(describing: error)) \(String(describing: status))"

    XCTAssertFalse(output.contains("root-secret"))
    XCTAssertFalse(output.contains("initial-refresh"))
  }

  private func pairedCoordinator(transport: SessionTransportFixture) async throws -> DeviceSessionCoordinator {
    try await pairedCoordinatorWithStore(transport: transport).0
  }

  private func pairedCoordinatorWithStore(
    transport: SessionTransportFixture
  ) async throws -> (DeviceSessionCoordinator, InMemoryDeviceCredentialStore) {
    let store = InMemoryDeviceCredentialStore()
    let coordinator = DeviceSessionCoordinator(
      transport: transport,
      credentialStore: store
    )
    try await coordinator.pair(origin: origin, code: "pairing-code", displayName: nil)
    return (coordinator, store)
  }

  private func pairingResponse() -> DevicePairingResponse {
    let identity = PairedDeviceIdentity(
      origin: origin, deviceID: deviceID, userID: userID,
      credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let credentials = DeviceCredentialSet(
      deviceSecret: "root-secret", accessCredential: "initial-access",
      refreshToken: "initial-refresh", refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_100)
    )
    return DevicePairingResponse(identity: identity, credentials: credentials)
  }

  private func rotated() -> DeviceSessionCredentials {
    DeviceSessionCredentials(
      accessCredential: "replacement-access", credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_200),
      refreshToken: "replacement-refresh", refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_300)
    )
  }
}

private actor SessionTransportFixture: PlatformDeviceTransport {
  private let pairing: DevicePairingResponse
  private let refreshResult: Result<DeviceSessionCredentials, Error>
  private let sessionResult: Result<DeviceSessionCredentials, Error>
  private var storedRefreshTokens: [String] = []
  private var sessionCount = 0
  private var refreshStarted: CheckedContinuation<Void, Never>?

  init(
    pairing: DevicePairingResponse,
    refresh: Result<DeviceSessionCredentials, Error>,
    session: Result<DeviceSessionCredentials, Error> = .failure(PlatformDeviceTransportError.unavailable)
  ) {
    self.pairing = pairing
    refreshResult = refresh
    sessionResult = session
  }

  var refreshTokens: [String] { storedRefreshTokens }
  var openedSessionCount: Int { sessionCount }

  func waitForRefreshToStart() async {
    guard storedRefreshTokens.isEmpty else { return }
    await withCheckedContinuation { refreshStarted = $0 }
  }

  func pair(_ request: DevicePairingRequest) async throws -> DevicePairingResponse { pairing }

  func refresh(origin: URL, refreshToken: String) async throws -> DeviceSessionCredentials {
    storedRefreshTokens.append(refreshToken)
    refreshStarted?.resume()
    refreshStarted = nil
    try? await Task.sleep(for: .milliseconds(10))
    return try refreshResult.get()
  }

  func openSession(
    origin: URL, deviceID: UUID, deviceSecret: String
  ) async throws -> DeviceSessionCredentials {
    sessionCount += 1
    return try sessionResult.get()
  }
}

private func XCTAssertThrowsErrorAsync(
  _ operation: @escaping @Sendable () async throws -> String
) async {
  do {
    _ = try await operation()
    XCTFail("the operation must fail")
  } catch {}
}

private func capturedError(
  _ operation: @escaping @Sendable () async throws -> String
) async -> Error? {
  do {
    _ = try await operation()
    return nil
  } catch {
    return error
  }
}
