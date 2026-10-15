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

/// One JSON file, `{"vaults":[...]}`, with the state of every watched vault.
/// Each save writes the whole file atomically.
public actor FileVaultChannelStateStore: VaultChannelStateStoring {
  private struct Document: Codable {
    var vaults: [VaultChannelState]
  }

  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load(vaultKey: String) async throws -> VaultChannelState? {
    try document().vaults.first { $0.vaultKey == vaultKey }
  }

  public func save(_ state: VaultChannelState) async throws {
    var vaults = try document().vaults.filter { $0.vaultKey != state.vaultKey }
    vaults.append(state)
    vaults.sort { $0.vaultKey < $1.vaultKey }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(Document(vaults: vaults)).write(to: fileURL, options: .atomic)
  }

  private func document() throws -> Document {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return Document(vaults: [])
    }
    return try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
  }
}
