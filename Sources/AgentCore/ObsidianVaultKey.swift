import Foundation

/// The `vault_key` of a vault: the vault id of Obsidian, which the plugin
/// sends as `app.appId`. Obsidian keeps it as the key of the vault in its
/// `obsidian.json`, so the plugin and the agent send the same key for the
/// same vault, and notes can keep one channel per vault.
public enum ObsidianVaultKey {
  private struct Config: Decodable {
    let vaults: [String: ObsidianConfigVault]
  }

  /// `obsidian.json` of the user. A sandboxed agent gets its container as the
  /// home directory, so the path starts from the home directory of the
  /// account.
  public static var userConfig: URL {
    let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/obsidian/obsidian.json")
  }

  /// The vault id of the vault at `vault`, read from `config`, or nil when
  /// the file cannot be read or names no vault at that path.
  public static func key(forVault vault: URL, config: URL) -> String? {
    guard let data = try? Data(contentsOf: config),
          let decoded = try? JSONDecoder().decode(Config.self, from: data) else {
      return nil
    }
    let wanted = canonical(vault.path)
    return decoded.vaults.sorted { $0.key < $1.key }.first { canonical($0.value.path) == wanted }?.key
  }

  /// Whether `config` decodes as the vault list of Obsidian.
  public static func isVaultList(_ config: URL) -> Bool {
    guard let data = try? Data(contentsOf: config) else {
      return false
    }
    return (try? JSONDecoder().decode(Config.self, from: data)) != nil
  }

  private static func canonical(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
  }
}

/// One vault of `obsidian.json`; only its folder is read.
private struct ObsidianConfigVault: Decodable {
  let path: String
}
