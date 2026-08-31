import Foundation

public struct PairedDeviceIdentity: Codable, Equatable, Hashable, Sendable {
  public let origin: URL
  public let deviceID: UUID
  public let userID: UUID
  public let credentialExpiresAt: Date

  public init(origin: URL, deviceID: UUID, userID: UUID, credentialExpiresAt: Date) {
    self.origin = origin
    self.deviceID = deviceID
    self.userID = userID
    self.credentialExpiresAt = credentialExpiresAt
  }
}

public struct DeviceCredentialSet: Codable, CustomStringConvertible, Equatable, Sendable {
  public let deviceSecret: String
  public let accessCredential: String
  public let refreshToken: String
  public let refreshExpiresAt: Date

  public init(
    deviceSecret: String,
    accessCredential: String,
    refreshToken: String,
    refreshExpiresAt: Date
  ) {
    self.deviceSecret = deviceSecret
    self.accessCredential = accessCredential
    self.refreshToken = refreshToken
    self.refreshExpiresAt = refreshExpiresAt
  }

  public var description: String {
    "DeviceCredentialSet(redacted)"
  }
}

public struct DevicePairingRequest: CustomStringConvertible, Equatable, Sendable {
  public let origin: URL
  public let code: String
  public let kind: String
  public let displayName: String?

  public init(origin: URL, code: String, kind: String, displayName: String?) {
    self.origin = origin
    self.code = code
    self.kind = kind
    self.displayName = displayName
  }

  public var description: String {
    "DevicePairingRequest(origin: \(origin), kind: \(kind), displayName: \(displayName ?? "nil"), code: redacted)"
  }
}

public struct DevicePairingResponse: Equatable, Sendable {
  public let identity: PairedDeviceIdentity
  public let credentials: DeviceCredentialSet

  public init(identity: PairedDeviceIdentity, credentials: DeviceCredentialSet) {
    self.identity = identity
    self.credentials = credentials
  }
}

public struct DeviceSessionCredentials: CustomStringConvertible, Equatable, Sendable {
  public let accessCredential: String
  public let credentialExpiresAt: Date
  public let refreshToken: String
  public let refreshExpiresAt: Date

  public init(
    accessCredential: String,
    credentialExpiresAt: Date,
    refreshToken: String,
    refreshExpiresAt: Date
  ) {
    self.accessCredential = accessCredential
    self.credentialExpiresAt = credentialExpiresAt
    self.refreshToken = refreshToken
    self.refreshExpiresAt = refreshExpiresAt
  }

  public var description: String {
    "DeviceSessionCredentials(redacted)"
  }
}

public protocol PlatformDeviceTransport: Sendable {
  func pair(_ request: DevicePairingRequest) async throws -> DevicePairingResponse
  func refresh(origin: URL, refreshToken: String) async throws -> DeviceSessionCredentials
  func openSession(
    origin: URL,
    deviceID: UUID,
    deviceSecret: String
  ) async throws -> DeviceSessionCredentials
}

public extension PlatformDeviceTransport {
  func refresh(origin: URL, refreshToken: String) async throws -> DeviceSessionCredentials {
    throw PlatformDeviceTransportError.unavailable
  }

  func openSession(
    origin: URL,
    deviceID: UUID,
    deviceSecret: String
  ) async throws -> DeviceSessionCredentials {
    throw PlatformDeviceTransportError.unavailable
  }
}

public protocol DeviceCredentialStoring: Sendable {
  func save(_ credentials: DeviceCredentialSet, for identity: PairedDeviceIdentity) async throws
  func load(for identity: PairedDeviceIdentity) async throws -> DeviceCredentialSet?
  func remove(for identity: PairedDeviceIdentity) async throws
}

/// Supplies short-lived device authority at request time and owns bounded recovery after a 401.
public protocol PlatformRequestAuthorizing: Sendable {
  func credentialForRequest() async throws -> String
  func recoverCredential(afterRejectedCredential credential: String) async throws -> String
  func authorizationWasRejected(_ credential: String) async
}

public enum DevicePairingStatus: Equatable, Sendable {
  case unpaired
  case paired(PairedDeviceIdentity)
  case rePairingRequired(PairedDeviceIdentity)
}

public enum DeviceCredentialError: Error, CustomStringConvertible, Sendable {
  case unavailable

  public var description: String {
    "Device credentials are unavailable."
  }
}
