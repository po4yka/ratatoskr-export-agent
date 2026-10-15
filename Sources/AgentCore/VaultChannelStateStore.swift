import Foundation

/// What a restart needs to resume the `cli` channel of one vault. It holds no
/// secret: the device credential stays in the Keychain.
public struct VaultChannelState: Codable, Equatable, Sendable {
  public var vaultKey: String
  public var connectionID: String
  public var committedSequence: UInt64

  public init(vaultKey: String, connectionID: String, committedSequence: UInt64) {
    self.vaultKey = vaultKey
    self.connectionID = connectionID
    self.committedSequence = committedSequence
  }

  enum CodingKeys: String, CodingKey {
    case vaultKey = "vault_key"
    case connectionID = "connection_id"
    case committedSequence = "committed_sequence"
  }
}

public protocol VaultChannelStateStoring: Sendable {
  func load(vaultKey: String) async throws -> VaultChannelState?
  func save(_ state: VaultChannelState) async throws
}

/// One JSON file with the state of every watched vault.
public actor FileVaultChannelStateStore: VaultChannelStateStoring {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load(vaultKey: String) async throws -> VaultChannelState? {
    nil
  }

  public func save(_ state: VaultChannelState) async throws {}
}
