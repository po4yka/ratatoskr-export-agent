import Foundation

/// The one-time grant of the owner to read `obsidian.json` from a sandboxed
/// agent: a security-scoped bookmark of the file, picked once in an open
/// panel. The `user-selected.read-write` entitlement allows it; no new
/// entitlement is needed.
public final class ObsidianConfigGrant: @unchecked Sendable {
  public enum GrantError: Error, Equatable {
    /// The picked file is not a vault list of Obsidian.
    case notTheVaultList
  }

  private let bookmarkFile: URL
  private let bookmarkStore: any FolderBookmarkStoring

  public init(bookmarkFile: URL, bookmarkStore: any FolderBookmarkStoring) {
    self.bookmarkFile = bookmarkFile
    self.bookmarkStore = bookmarkStore
  }

  public var isGranted: Bool {
    FileManager.default.fileExists(atPath: bookmarkFile.path)
  }

  /// Saves a bookmark of `config` when it is a vault list of Obsidian. The
  /// open panel that picked it gives this process access to read it now.
  public func grant(config: URL) throws {
    guard config.lastPathComponent == "obsidian.json", ObsidianVaultKey.isVaultList(config) else {
      throw GrantError.notTheVaultList
    }
    let data = try bookmarkStore.makeBookmarkData(for: config)
    try FileManager.default.createDirectory(at: bookmarkFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: bookmarkFile, options: .atomic)
  }

  /// The vault id of `vault`, read through the bookmark; nil without a grant.
  /// An access that this call begins, it also ends.
  public func key(forVault vault: URL) -> String? {
    guard let data = try? Data(contentsOf: bookmarkFile),
          let resolved = try? bookmarkStore.resolvedFolder(from: data) else {
      return nil
    }
    let began = bookmarkStore.startAccessing(resolved)
    defer {
      if began {
        bookmarkStore.stopAccessing(resolved)
      }
    }
    return ObsidianVaultKey.key(forVault: vault, config: resolved.url)
  }
}
