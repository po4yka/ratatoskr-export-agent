import Foundation

/// The files of one vault that a queued write may touch.
///
/// A path from the queue is relative to the vault root. A path that is
/// absolute, that has an empty, `.` or `..` segment, a segment that starts
/// with `.` (`.obsidian/`, `.trash/`) or ends in `.` or a space, or that holds
/// `\`, `:`, a C0 control character or DEL, is refused (the rule of contract
/// `write-request.v1` and of the plugin). A path is also refused when its
/// nearest existing folder resolves outside the vault through a symbolic
/// link, or when the file itself is a symbolic link.
struct VaultFileAccess: Sendable {
  let root: URL

  init(root: URL) {
    self.root = root.resolvingSymlinksInPath().standardizedFileURL
  }

  /// The URL of `path` inside the vault, or nil when it is refused.
  func url(of path: String) -> URL? {
    let refused = path.unicodeScalars.contains { $0 == "\\" || $0 == ":" || $0.value < 0x20 || $0.value == 0x7F }
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !refused, segments.first?.lowercased() != ".obsidian", segments.allSatisfy(Self.isSafe) else {
      return nil
    }
    let url = root.appendingPathComponent(path)
    var folder = url.deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: folder.path), folder.pathComponents.count > 1 {
      folder = folder.deletingLastPathComponent()
    }
    let resolved = folder.resolvingSymlinksInPath().standardizedFileURL.path
    guard resolved == root.path || resolved.hasPrefix(root.path + "/") else {
      return nil
    }
    let kind = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
    return kind == .typeSymbolicLink ? nil : url
  }

  /// A segment is not empty, does not start with `.`, and does not end in
  /// `.` or a space.
  private static func isSafe(_ segment: Substring) -> Bool {
    !segment.isEmpty && !segment.hasPrefix(".") && !segment.hasSuffix(".") && !segment.hasSuffix(" ")
  }

  /// The SHA-256 of the file, or nil when there is no file. A path that is
  /// not a regular file (a folder) has no hash and throws.
  func sha256(at url: URL) throws -> String? {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }
    guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
      throw CocoaError(.fileReadUnknown)
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
