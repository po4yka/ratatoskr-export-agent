import AgentCore
import Foundation
import XCTest

final class PairingOnboardingTests: XCTestCase {
  func testRelaunchRestoresNonSecretIdentityAndKeychainSession() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "identity-\(UUID())")
    let identityURL = directory.appending(path: "paired-device.json")
    let identityStore = FileDeviceIdentityStore(fileURL: identityURL)
    let credentialStore = InMemoryDeviceCredentialStore()
    let transport = OnboardingTransportFixture()
    let first = DeviceSessionCoordinator(
      transport: transport, credentialStore: credentialStore, identityStore: identityStore
    )
    try await first.pair(
      origin: URL(string: "https://ratatoskr.example")!, code: "one-time-code", displayName: "Mac"
    )

    let relaunched = DeviceSessionCoordinator(
      transport: transport, credentialStore: credentialStore, identityStore: identityStore
    )
    try await relaunched.restore()

    let restoredStatus = await relaunched.status
    let identity = transport.identity
    let accessCredential = try await relaunched.credentialForRequest()
    XCTAssertEqual(restoredStatus, .paired(identity))
    XCTAssertEqual(accessCredential, "initial-access")
    try assertIdentityDocumentContainsNoSecrets(at: identityURL)

    let rotated = try await relaunched.recoverCredential(
      afterRejectedCredential: "initial-access"
    )
    XCTAssertEqual(rotated, "rotated-access")
    await relaunched.authorizationWasRejected("rotated-access")
    let revokedStatus = await relaunched.status
    XCTAssertEqual(revokedStatus, .rePairingRequired(identity))
    XCTAssertTrue(FileManager.default.fileExists(atPath: identityURL.path))

    try await relaunched.pair(
      origin: identity.origin, code: "replacement-code", displayName: "Mac"
    )
    let repairedStatus = await relaunched.status
    XCTAssertEqual(repairedStatus, .paired(identity))
  }

  private func assertIdentityDocumentContainsNoSecrets(at identityURL: URL) throws {
    let identityBytes = try String(contentsOf: identityURL, encoding: .utf8)
    XCTAssertFalse(identityBytes.contains("root-secret"))
    XCTAssertFalse(identityBytes.contains("initial-access"))
    XCTAssertFalse(identityBytes.contains("initial-refresh"))
  }
}

private actor OnboardingTransportFixture: PlatformDeviceTransport {
  let identity = PairedDeviceIdentity(
    origin: URL(string: "https://ratatoskr.example")!,
    deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000241")!,
    userID: UUID(uuidString: "00000000-0000-0000-0000-000000000242")!,
    credentialExpiresAt: Date(timeIntervalSince1970: 1_900_000_000)
  )

  func pair(_: DevicePairingRequest) async throws -> DevicePairingResponse {
    DevicePairingResponse(
      identity: identity,
      credentials: DeviceCredentialSet(
        deviceSecret: "root-secret", accessCredential: "initial-access",
        refreshToken: "initial-refresh", refreshExpiresAt: Date(timeIntervalSince1970: 1_900_000_100)
      )
    )
  }

  func refresh(origin _: URL, refreshToken _: String) async throws -> DeviceSessionCredentials {
    DeviceSessionCredentials(
      accessCredential: "rotated-access",
      credentialExpiresAt: Date(timeIntervalSince1970: 1_900_000_200),
      refreshToken: "rotated-refresh",
      refreshExpiresAt: Date(timeIntervalSince1970: 1_900_000_300)
    )
  }
}
