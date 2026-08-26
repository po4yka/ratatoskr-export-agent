import AgentCore
import XCTest

final class DeviceCredentialStoreTests: XCTestCase {
  private let origin = URL(string: "https://ratatoskr.example")!
  private let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
  private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!

  func testCredentialSetRoundTripsForMatchingOriginAndDevice() async throws {
    let store = InMemoryDeviceCredentialStore()
    let identity = makeIdentity()
    let credentials = makeCredentials()

    try await store.save(credentials, for: identity)

    let loadedCredentials = try await store.load(for: identity)
    XCTAssertEqual(loadedCredentials, credentials)
  }

  func testCredentialSetCannotBeReadThroughDifferentIdentity() async throws {
    let store = InMemoryDeviceCredentialStore()
    let identity = makeIdentity()
    let otherIdentity = PairedDeviceIdentity(
      origin: origin,
      deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
      userID: userID,
      credentialExpiresAt: identity.credentialExpiresAt
    )
    try await store.save(makeCredentials(), for: identity)

    let loadedCredentials = try await store.load(for: otherIdentity)
    XCTAssertNil(loadedCredentials)
  }

  func testStoreFailurePublishesNoPartialPairingState() async throws {
    let secret = "fixture-device-secret"
    let coordinator = DeviceSessionCoordinator(
      transport: StoreFailureTransport(response: makeResponse()),
      credentialStore: FailingCredentialStore())

    do {
      try await coordinator.pair(origin: origin, code: secret, displayName: nil)
      XCTFail("a credential store failure must stop pairing")
    } catch {
      let status = await coordinator.status
      XCTAssertEqual(status, .unpaired)
      XCTAssertFalse(error.localizedDescription.contains(secret))
    }
  }

  func testCredentialModelsRedactSecretsWhenDescribed() {
    let credentials = makeCredentials()
    let request = DevicePairingRequest(
      origin: origin,
      code: "fixture-pairing-code",
      kind: "export_agent",
      displayName: "Fixture Mac"
    )
    let session = DeviceSessionCredentials(
      accessCredential: "fixture-session-access",
      credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_200),
      refreshToken: "fixture-session-refresh",
      refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_300)
    )

    let output = "\(credentials) \(request) \(session)"

    for secret in [
      "fixture-device-secret", "fixture-access-credential", "fixture-refresh-token",
      "fixture-pairing-code", "fixture-session-access", "fixture-session-refresh",
    ] {
      XCTAssertFalse(output.contains(secret))
    }
  }

  func testMacOSKeychainRoundTripAndDelete() async throws {
    guard ProcessInfo.processInfo.environment["RATATOSKR_KEYCHAIN_INTEGRATION"] == "1" else {
      throw XCTSkip("set RATATOSKR_KEYCHAIN_INTEGRATION=1 on a macOS Keychain-capable runner")
    }
    let service = "com.po4yka.ratatoskr.export-agent.tests.\(UUID().uuidString)"
    let identity = makeIdentity()
    let credentials = makeCredentials()
    let writer = KeychainDeviceCredentialStore(service: service)

    try await writer.save(credentials, for: identity)
    let reader = KeychainDeviceCredentialStore(service: service)
    let restoredCredentials = try await reader.load(for: identity)
    XCTAssertEqual(restoredCredentials, credentials)
    try await reader.remove(for: identity)
    let removedCredentials = try await reader.load(for: identity)
    XCTAssertNil(removedCredentials)
  }

  private func makeIdentity() -> PairedDeviceIdentity {
    PairedDeviceIdentity(
      origin: origin,
      deviceID: deviceID,
      userID: userID,
      credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }

  private func makeCredentials() -> DeviceCredentialSet {
    DeviceCredentialSet(
      deviceSecret: "fixture-device-secret",
      accessCredential: "fixture-access-credential",
      refreshToken: "fixture-refresh-token",
      refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_100)
    )
  }

  private func makeResponse() -> DevicePairingResponse {
    DevicePairingResponse(identity: makeIdentity(), credentials: makeCredentials())
  }
}

private struct StoreFailureTransport: PlatformDeviceTransport {
  let response: DevicePairingResponse

  func pair(_ request: DevicePairingRequest) async throws -> DevicePairingResponse {
    response
  }
}

private actor FailingCredentialStore: DeviceCredentialStoring {
  func save(_ credentials: DeviceCredentialSet, for identity: PairedDeviceIdentity) async throws {
    throw DeviceCredentialError.unavailable
  }

  func load(for identity: PairedDeviceIdentity) async throws -> DeviceCredentialSet? {
    nil
  }

  func remove(for identity: PairedDeviceIdentity) async throws {}
}
