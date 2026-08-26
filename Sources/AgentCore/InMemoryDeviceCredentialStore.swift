import Foundation

/// Test-only credential store for deterministic coordinator tests.
public actor InMemoryDeviceCredentialStore: DeviceCredentialStoring {
  private var credentialsByIdentity: [PairedDeviceIdentity: DeviceCredentialSet] = [:]

  public init() {}

  public func save(
    _ credentials: DeviceCredentialSet,
    for identity: PairedDeviceIdentity
  ) async throws {
    credentialsByIdentity[identity] = credentials
  }

  public func load(for identity: PairedDeviceIdentity) async throws -> DeviceCredentialSet? {
    credentialsByIdentity[identity]
  }

  public func remove(for identity: PairedDeviceIdentity) async throws {
    credentialsByIdentity[identity] = nil
  }
}
