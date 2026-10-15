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

  public func load() throws -> [WatchedVault] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return []
    }
    return try JSONDecoder().decode(WatchedVaultDocument.self, from: Data(contentsOf: fileURL)).vaults
  }

  public func save(_ vaults: [WatchedVault]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder.encode(WatchedVaultDocument(vaults: vaults)).write(to: fileURL, options: .atomic)
  }
}

private struct WatchedVaultDocument: Codable {
  var vaults: [WatchedVault]
}

/// The vaults that the agent watches for the `cli` channel. The key of a
/// vault is its vault id of Obsidian, as the plugin sends it; when the agent
/// cannot read it (no `obsidian.json` entry, or a sandbox without access),
/// the registry generates a key once and keeps it.
@MainActor
public final class WatchedVaultRegistry {
  public private(set) var vaults: [WatchedVault]
  private let store: any WatchedVaultStoring
  private let bookmarkStore: any FolderBookmarkStoring
  private let vaultKey: (URL) -> String?
  private let newKey: () -> String

  public init(
    store: any WatchedVaultStoring,
    bookmarkStore: any FolderBookmarkStoring,
    vaultKey: @escaping (URL) -> String? = { ObsidianVaultKey.key(forVault: $0, config: ObsidianVaultKey.userConfig) },
    newKey: @escaping () -> String = { UUID().uuidString.lowercased() }
  ) throws {
    self.store = store
    self.bookmarkStore = bookmarkStore
    self.vaultKey = vaultKey
    self.newKey = newKey
    vaults = try store.load()
  }

  /// Adds a picked vault folder. The same folder, or a folder with the key of
  /// a known vault, is that vault.
  @discardableResult
  public func addVault(at url: URL) throws -> WatchedVault {
    let key = vaultKey(url)
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    if let known = vaults.first(where: { $0.vaultKey == key || folderPath(of: $0) == path }) {
      return known
    }
    let bookmarkData = try bookmarkStore.makeBookmarkData(for: url)
    let vault = WatchedVault(
      id: UUID(), displayName: url.standardizedFileURL.lastPathComponent, vaultKey: key ?? newKey(), bookmarkData: bookmarkData
    )
    try store.save(vaults + [vault])
    vaults.append(vault)
    return vault
  }

  /// The vaults whose folders resolve and can be read, with access begun.
  public func runtimeVaults() -> [RuntimeVault] {
    []
  }

  /// Removes a vault and ends the access to its folder.
  public func removeVault(id: UUID) {
    guard let index = vaults.firstIndex(where: { $0.id == id }) else {
      return
    }
    let vault = vaults.remove(at: index)
    if let resolved = try? bookmarkStore.resolvedFolder(from: vault.bookmarkData) {
      bookmarkStore.stopAccessing(resolved)
    }
    try? store.save(vaults)
  }

  private func folderPath(of vault: WatchedVault) -> String? {
    (try? bookmarkStore.resolvedFolder(from: vault.bookmarkData))?.url.resolvingSymlinksInPath().standardizedFileURL.path
  }
}
