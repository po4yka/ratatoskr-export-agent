import Foundation

/// One watched Obsidian vault: its identity, the folder name that Obsidian
/// shows, the `vault_key` of its `cli` channel, and the bookmark of its
/// folder. It holds no secret.
public struct WatchedVault: Codable, Equatable, Sendable {
  public var id: UUID
  public var displayName: String
  public var vaultKey: String
  public var bookmarkData: Data

  public init(id: UUID, displayName: String, vaultKey: String, bookmarkData: Data) {
    self.id = id
    self.displayName = displayName
    self.vaultKey = vaultKey
    self.bookmarkData = bookmarkData
  }

  enum CodingKeys: String, CodingKey {
    case id
    case displayName = "display_name"
    case vaultKey = "vault_key"
    case bookmarkData = "bookmark"
  }
}

public protocol WatchedVaultStoring: Sendable {
  func load() throws -> [WatchedVault]
  func save(_ vaults: [WatchedVault]) throws
}

/// `{"vaults":[...]}` in one JSON file of the support directory.
public struct FileWatchedVaultStore: WatchedVaultStoring {
  private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> [WatchedVault] { [] }

  public func save(_ vaults: [WatchedVault]) throws {}
}

/// The vaults that the agent watches for the `cli` channel.
public final class WatchedVaultRegistry {
  public private(set) var vaults: [WatchedVault] = []

  public init(
    store: any WatchedVaultStoring,
    bookmarkStore: any FolderBookmarkStoring,
    vaultKey: @escaping (URL) -> String? = { ObsidianVaultKey.key(forVault: $0, config: ObsidianVaultKey.userConfig) },
    newKey: @escaping () -> String = { UUID().uuidString.lowercased() }
  ) throws {}

  /// Adds a picked vault folder. The same folder is one vault.
  @discardableResult
  public func addVault(at url: URL) throws -> WatchedVault {
    WatchedVault(id: UUID(), displayName: "", vaultKey: "", bookmarkData: Data())
  }

  /// Removes a vault and ends the access to its folder.
  public func removeVault(id: UUID) {}
}
