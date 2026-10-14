import Foundation

/// Path rules of the vault mode: NFC keys, hidden segments, and the disk walk.
enum VaultPaths {
  /// The path with symbolic links resolved, so `/var/...` and the
  /// `/private/var/...` that FSEvents reports compare equal. For a path that
  /// no longer exists, the nearest existing parent is resolved.
  static func canonical(_ path: String) -> String {
    if let resolved = realpath(path, nil) {
      defer {
        free(resolved)
      }
      return String(cString: resolved)
    }
    let parent = (path as NSString).deletingLastPathComponent
    guard !parent.isEmpty, parent != path else {
      return path
    }
    return (canonical(parent) as NSString).appendingPathComponent((path as NSString).lastPathComponent)
  }

  /// Unicode NFC, the form that `ratatoskr-notes` keys files by (design D7).
  static func nfc(_ path: String) -> String {
    path.precomposedStringWithCanonicalMapping
  }

  /// False for a path with a segment that starts with `.`, such as
  /// `.obsidian/`, `.trash/` or `.DS_Store`.
  static func isIndexed(_ relative: String) -> Bool {
    !relative.split(separator: "/").contains { $0.hasPrefix(".") }
  }

  static func isInside(_ key: String, scope: String) -> Bool {
    scope.isEmpty || key == scope || key.hasPrefix(scope + "/")
  }

  /// The byte size of a regular file, or nil for anything else. Does not
  /// follow a symbolic link.
  static func regularFileSize(_ path: String) -> Int? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      attributes[.type] as? FileAttributeType == .typeRegular
    else {
      return nil
    }
    return (attributes[.size] as? NSNumber)?.intValue
  }

  /// The indexed regular files at `diskPath`, keyed by NFC relative path.
  /// `scope` is the NFC relative path of `diskPath`.
  static func files(at diskPath: String, scope: String) -> [String: URL] {
    let prefix = scope.isEmpty ? "" : scope + "/"
    if regularFileSize(diskPath) != nil {
      return [scope: URL(fileURLWithPath: diskPath)]
    }
    guard let walker = FileManager.default.enumerator(atPath: diskPath) else {
      return [:]
    }
    var found: [String: URL] = [:]
    while let subpath = walker.nextObject() as? String {
      let name = (subpath as NSString).lastPathComponent
      if name.hasPrefix(".") {
        // Only a directory: on a file, the walker would skip its siblings.
        if walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
          walker.skipDescendants()
        }
        continue
      }
      let url = URL(fileURLWithPath: diskPath).appendingPathComponent(subpath)
      if regularFileSize(url.path) != nil {
        found[prefix + nfc(subpath)] = url
      }
    }
    return found
  }
}
