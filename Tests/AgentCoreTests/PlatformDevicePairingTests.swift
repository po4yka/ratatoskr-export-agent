import AgentCore
import XCTest

final class PlatformDevicePairingTests: XCTestCase {
  private let origin = URL(string: "https://ratatoskr.example")!
  private let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  private let userID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

  func testPairingPostsExportAgentAndStoresOnlyAfter201() async throws {
    let response = pairingResponse()
    let transport = PairingTransportFixture(result: .success(response))
    let store = CredentialStoreFixture()
    let coordinator = DeviceSessionCoordinator(transport: transport, credentialStore: store)

    try await coordinator.pair(origin: origin, code: "fixture-pairing-code", displayName: "Mac")

    let request = await transport.requests.single
    let status = await coordinator.status
    let storedCredentials = await store.credentials(for: response.identity)
    XCTAssertEqual(request?.origin, origin)
    XCTAssertEqual(request?.kind, "export_agent")
    XCTAssertEqual(request?.displayName, "Mac")
    XCTAssertEqual(status, .paired(response.identity))
    XCTAssertEqual(storedCredentials, response.credentials)
  }

  func testPairingRefusalDoesNotPersistPartialState() async throws {
    let transport = PairingTransportFixture(result: .failure(DeviceCredentialError.unavailable))
    let store = CredentialStoreFixture()
    let coordinator = DeviceSessionCoordinator(transport: transport, credentialStore: store)

    do {
      try await coordinator.pair(origin: origin, code: "fixture-pairing-code", displayName: nil)
      XCTFail("a refused pairing code must fail")
    } catch {
      let status = await coordinator.status
      let storeCount = await store.count
      XCTAssertEqual(status, .unpaired)
      XCTAssertEqual(storeCount, 0)
    }
  }

  private func pairingResponse() -> DevicePairingResponse {
    let identity = PairedDeviceIdentity(
      origin: origin,
      deviceID: deviceID,
      userID: userID,
      credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let credentials = DeviceCredentialSet(
      deviceSecret: "fixture-device-secret",
      accessCredential: "fixture-access-credential",
      refreshToken: "fixture-refresh-token",
      refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_100)
    )
    return DevicePairingResponse(identity: identity, credentials: credentials)
  }
}

private actor PairingTransportFixture: PlatformDeviceTransport {
  private var storedRequests: [DevicePairingRequest] = []
  private let result: Result<DevicePairingResponse, Error>

  init(result: Result<DevicePairingResponse, Error>) {
    self.result = result
  }

  var requests: [DevicePairingRequest] {
    storedRequests
  }

  func pair(_ request: DevicePairingRequest) async throws -> DevicePairingResponse {
    storedRequests.append(request)
    return try result.get()
  }
}

private actor CredentialStoreFixture: DeviceCredentialStoring {
  private var storedCredentials: [PairedDeviceIdentity: DeviceCredentialSet] = [:]

  var count: Int {
    storedCredentials.count
  }

  func credentials(for identity: PairedDeviceIdentity) -> DeviceCredentialSet? {
    storedCredentials[identity]
  }

  func save(_ credentials: DeviceCredentialSet, for identity: PairedDeviceIdentity) async throws {
    storedCredentials[identity] = credentials
  }

  func load(for identity: PairedDeviceIdentity) async throws -> DeviceCredentialSet? {
    storedCredentials[identity]
  }

  func remove(for identity: PairedDeviceIdentity) async throws {
    storedCredentials[identity] = nil
  }
}

private extension Array {
  var single: Element? {
    count == 1 ? first : nil
  }
}
