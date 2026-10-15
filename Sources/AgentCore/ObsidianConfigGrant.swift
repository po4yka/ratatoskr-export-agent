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

  public init(bookmarkFile: URL, bookmarkStore: any FolderBookmarkStoring) {}

  public var isGranted: Bool {
    false
  }

  /// Saves a bookmark of `config` when it is a vault list of Obsidian.
  public func grant(config: URL) throws {}

  /// The vault id of `vault`, read through the bookmark; nil without a grant.
  public func key(forVault vault: URL) -> String? {
    nil
  }
}
