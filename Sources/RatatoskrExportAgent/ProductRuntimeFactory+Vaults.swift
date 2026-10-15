import AgentCore
import Foundation

extension ProductRuntimeFactory {
  /// The watched Obsidian vaults, in `vault-preferences.json` of the support
  /// directory.
  static func makeVaultRegistry(support: URL) throws -> WatchedVaultRegistry {
    try WatchedVaultRegistry(
      store: FileWatchedVaultStore(fileURL: support.appending(path: "vault-preferences.json")),
      bookmarkStore: SecurityScopedBookmarkStore()
    )
  }
}
