import Foundation

public actor DeviceSessionCoordinator: PlatformRequestAuthorizing {
  private let transport: any PlatformDeviceTransport
  private let credentialStore: any DeviceCredentialStoring
  private let identityStore: any DeviceIdentityStoring
  private var activeRefresh: Task<DeviceSessionCredentials, Error>?

  public private(set) var status: DevicePairingStatus = .unpaired

  public init(
    transport: any PlatformDeviceTransport,
    credentialStore: any DeviceCredentialStoring,
    identityStore: any DeviceIdentityStoring = InMemoryDeviceIdentityStore()
  ) {
    self.transport = transport
    self.credentialStore = credentialStore
    self.identityStore = identityStore
  }

  public func restore() async throws {
    guard let identity = try await identityStore.load() else {
      status = .unpaired
      return
    }
    if try await credentialStore.load(for: identity) == nil {
      status = .rePairingRequired(identity)
    } else {
      status = .paired(identity)
    }
  }

  public func pair(origin: URL, code: String, displayName: String?) async throws {
    let request = DevicePairingRequest(
      origin: origin, code: code, kind: "export_agent", displayName: displayName
    )
    let response = try await transport.pair(request)
    try await credentialStore.save(response.credentials, for: response.identity)
    do {
      try await identityStore.save(response.identity)
    } catch {
      try? await credentialStore.remove(for: response.identity)
      throw error
    }
    status = .paired(response.identity)
  }

  public func unpair() async throws {
    switch status {
    case let .paired(identity), let .rePairingRequired(identity):
      try await credentialStore.remove(for: identity)
    case .unpaired:
      break
    }
    try await identityStore.remove()
    status = .unpaired
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

  public func credentialForRequest() async throws -> String {
    guard case let .paired(identity) = status,
          let credentials = try await credentialStore.load(for: identity) else {
      throw DeviceCredentialError.unavailable
    }
    return credentials.accessCredential
  }

  public func recoverCredential(afterRejectedCredential credential: String) async throws -> String {
    guard case let .paired(identity) = status,
          let current = try await credentialStore.load(for: identity) else {
      throw DeviceCredentialError.unavailable
    }
    if current.accessCredential != credential {
      return current.accessCredential
    }
    return try await refreshedAccessCredential()
  }

  public func authorizationWasRejected(_ credential: String) async {
    guard case let .paired(identity) = status,
          let current = try? await credentialStore.load(for: identity),
          current.accessCredential == credential else {
      return
    }
    try? await credentialStore.remove(for: identity)
    status = .rePairingRequired(identity)
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

public extension DeviceSessionCoordinator {
  func pairedIdentity() -> PairedDeviceIdentity? {
    switch status {
    case let .paired(identity), let .rePairingRequired(identity): identity
    case .unpaired: nil
    }
  }
}
