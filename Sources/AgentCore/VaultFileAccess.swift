import Foundation

/// The files of one vault that a queued write may touch.
///
/// A path from the queue is relative to the vault root. A path that is
/// absolute, that has an empty, `.` or `..` segment, or a segment that starts
/// with `.` (`.obsidian/`, `.trash/`) is refused. A path is also refused when
/// its nearest existing folder resolves outside the vault through a symbolic
/// link, or when the file itself is a symbolic link.
struct VaultFileAccess: Sendable {
  let root: URL

  init(root: URL) {
    self.root = root.resolvingSymlinksInPath().standardizedFileURL
  }

  /// The URL of `path` inside the vault, or nil when it is refused.
  func url(of path: String) -> URL? {
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !segments.isEmpty, segments.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") }) else {
      return nil
    }
    let url = root.appendingPathComponent(path)
    var folder = url.deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: folder.path) {
      folder = folder.deletingLastPathComponent()
    }
    let resolved = folder.resolvingSymlinksInPath().standardizedFileURL.path
    guard resolved == root.path || resolved.hasPrefix(root.path + "/") else {
      return nil
    }
    let kind = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    return kind == .typeSymbolicLink ? nil : url
  }

  /// The SHA-256 of the file, or nil when there is no file.
  func sha256(at url: URL) throws -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    return try StreamingHasher().fingerprint(at: url).sha256Hex
  }

  /// Writes `data` to a temporary file in the folder of `url` and renames it
  /// over `url`, so a reader sees the old bytes or the new bytes. The name of
  /// the temporary file starts with `.`, so the watcher does not report it.
  func write(_ data: Data, to url: URL) throws {
    let folder = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let temporary = folder.appendingPathComponent(".ratatoskr-\(UUID().uuidString).tmp")
    try data.write(to: temporary)
    guard rename(temporary.path, url.path) == 0 else {
      let code = errno
      try? FileManager.default.removeItem(at: temporary)
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
  }
}
