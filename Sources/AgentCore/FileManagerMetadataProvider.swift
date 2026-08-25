import Foundation

/// FileManager-backed filesystem facts for stability detection.
///
/// `attributesOfItem` uses lstat semantics, so a symlink reports its own
/// type instead of the target's and is refused as non-regular upstream.
public struct FileManagerMetadataProvider: FileMetadataProviding {
  public init() {}

  private var fileManager: FileManager {
    FileManager.default
  }

  public func snapshot(ofItemAtPath path: String) -> FileSnapshot? {
    guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
      return nil
    }
    guard let size = (attributes[.size] as? NSNumber)?.intValue else {
      return nil
    }
    guard let modifiedAt = attributes[.modificationDate] as? Date else {
      return nil
    }
    return FileSnapshot(byteSize: size, modifiedAt: modifiedAt)
  }

  public func isRegularFile(atPath path: String) -> Bool {
    guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
      return false
    }
    return (attributes[.type] as? FileAttributeType) == .typeRegular
  }

  public func isReadableFile(atPath path: String) -> Bool {
    fileManager.isReadableFile(atPath: path)
  }

  /// Advisory writer-hold probe. Darwin has no way to ask whether another
  /// process holds a handle open, so this attempts to obtain a write handle
  /// without creating or truncating; refusal (permissions, EBUSY, ELOOP)
  /// counts as a detected hold, while success proves nothing beyond that no
  /// exclusive lock was met. Quiet-period evidence carries the guarantee.
  public func writerHoldDetected(atPath path: String) -> Bool {
    let descriptor = Darwin.open(path, O_WRONLY | O_NOFOLLOW)
    guard descriptor >= 0 else {
      return true
    }
    Darwin.close(descriptor)
    return false
  }

  public func contentsOfDirectory(at url: URL) throws -> [URL] {
    try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
  }
}
