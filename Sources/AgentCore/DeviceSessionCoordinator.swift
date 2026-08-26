import Foundation

public actor DeviceSessionCoordinator {
  private let transport: any PlatformDeviceTransport
  private let credentialStore: any DeviceCredentialStoring
  private var activeRefresh: Task<DeviceSessionCredentials, Error>?

  public private(set) var status: DevicePairingStatus = .unpaired

  public init(
    transport: any PlatformDeviceTransport,
    credentialStore: any DeviceCredentialStoring
  ) {
    self.transport = transport
    self.credentialStore = credentialStore
  }

  public func pair(origin: URL, code: String, displayName: String?) async throws {
    let request = DevicePairingRequest(
      origin: origin, code: code, kind: "export_agent", displayName: displayName
    )
    let response = try await transport.pair(request)
    try await credentialStore.save(response.credentials, for: response.identity)
    status = .paired(response.identity)
  }

  public func refreshedAccessCredential() async throws -> String {
    if let activeRefresh {
      return try await activeRefresh.value.accessCredential
    }
    guard case let .paired(identity) = status,
          let credentials = try await credentialStore.load(for: identity) else {
      throw DeviceCredentialError.unavailable
    }
    let refresh = Task {
      try await Self.rotate(
        identity: identity,
        credentials: credentials,
        transport: transport,
        credentialStore: credentialStore
      )
    }
    activeRefresh = refresh
    defer { activeRefresh = nil }
    do {
      return try await refresh.value.accessCredential
    } catch PlatformDeviceTransportError.refused {
      try? await credentialStore.remove(for: identity)
      status = .rePairingRequired(identity)
      throw DeviceCredentialError.unavailable
    }
  }

  private static func rotate(
    identity: PairedDeviceIdentity,
    credentials: DeviceCredentialSet,
    transport: any PlatformDeviceTransport,
    credentialStore: any DeviceCredentialStoring
  ) async throws -> DeviceSessionCredentials {
    let session: DeviceSessionCredentials
    do {
      session = try await transport.refresh(origin: identity.origin, refreshToken: credentials.refreshToken)
    } catch PlatformDeviceTransportError.refused {
      session = try await transport.openSession(
        origin: identity.origin, deviceID: identity.deviceID, deviceSecret: credentials.deviceSecret
      )
    }
    let replacement = DeviceCredentialSet(
      deviceSecret: credentials.deviceSecret,
      accessCredential: session.accessCredential,
      refreshToken: session.refreshToken,
      refreshExpiresAt: session.refreshExpiresAt
    )
    try await credentialStore.save(replacement, for: identity)
    return session
  }
}
