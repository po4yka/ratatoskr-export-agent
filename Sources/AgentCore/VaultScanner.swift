import Foundation

/// Compares the disk under a vault root with the last known index and gives
/// the observations that make the index equal to the disk.
///
/// File system events only name the paths to compare; the disk decides. A
/// directory path compares its full subtree, so a folder rename gives one
/// delete and one create per file. Paths are NFC and relative to the vault
/// root. A path with a segment that starts with `.` is not indexed, as the
/// vault API of the plugin does not report it, and neither is a symbolic link
/// or a file larger than `maximumByteLength`.
public struct VaultScanner: Sendable {
  /// The default size limit of design D7 (64 MiB).
  public static let defaultMaximumByteLength = 64 * 1024 * 1024

  public let rootPath: String
  public let maximumByteLength: Int
  private let hasher: StreamingHasher

  /// NFC relative path to the fingerprint of the bytes last observed there.
  public private(set) var index: [String: ArchiveFingerprint] = [:]

  public init(
    root: URL,
    maximumByteLength: Int = VaultScanner.defaultMaximumByteLength,
    hasher: StreamingHasher = StreamingHasher()
  ) {
    rootPath = VaultPaths.canonical(root.path)
    self.maximumByteLength = maximumByteLength
    self.hasher = hasher
  }

  /// Compares the whole vault, for the first run and for a rescan request.
  public mutating func rescan() -> [VaultObservation] {
    compare(scope: "", diskPath: rootPath)
  }

  /// Compares each named absolute path. A path outside the root or a hidden
  /// path gives nothing.
  public mutating func scan(paths: [String]) -> [VaultObservation] {
    var observations: [VaultObservation] = []
    for path in Set(paths.compactMap(relativePath(of:))).sorted() {
      observations += compare(scope: VaultPaths.nfc(path), diskPath: rootPath + "/" + path)
    }
    return observations
  }

  private func relativePath(of absolute: String) -> String? {
    let canonical = VaultPaths.canonical(absolute)
    if canonical == rootPath {
      return ""
    }
    guard canonical.hasPrefix(rootPath + "/") else {
      return nil
    }
    let relative = String(canonical.dropFirst(rootPath.count + 1))
    return VaultPaths.isIndexed(relative) ? relative : nil
  }

  /// Makes the index under `scope` equal to the disk at `diskPath`.
  private mutating func compare(scope: String, diskPath: String) -> [VaultObservation] {
    let current = VaultPaths.files(at: diskPath, scope: scope).compactMapValues(fingerprint)
    var deleted: [VaultObservation] = []
    for key in index.keys.sorted() where VaultPaths.isInside(key, scope: scope) && current[key] == nil {
      if let entry = index.removeValue(forKey: key) {
        deleted.append(.deleted(path: key, sha256: entry.sha256Hex))
      }
    }
    var written: [VaultObservation] = []
    for (key, found) in current.sorted(by: { $0.key < $1.key }) {
      let known = index.updateValue(found, forKey: key)
      if known == nil {
        written.append(.created(path: key, sha256: found.sha256Hex, byteLength: found.byteSize))
      } else if known != found {
        written.append(.modified(path: key, sha256: found.sha256Hex, byteLength: found.byteSize))
      }
    }
    return deleted + written
  }

  private func fingerprint(_ url: URL) -> ArchiveFingerprint? {
    guard let size = VaultPaths.regularFileSize(url.path), size <= maximumByteLength else {
      return nil
    }
    return try? hasher.fingerprint(at: url)
  }
}
