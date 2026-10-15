import Foundation

/// The `vault_key` of a vault: the vault id of Obsidian, which the plugin
/// sends as `app.appId`. Obsidian keeps it as the key of the vault in its
/// `obsidian.json`.
public enum ObsidianVaultKey {
  /// The vault id of the vault at `vault`, read from `config`, or nil.
  public static func key(forVault vault: URL, config: URL) -> String? {
    nil
  }
}
