import Foundation

/// One file system fact about a vault file, after the agent read the disk.
public enum VaultObservation: Equatable, Sendable {
  case created(path: String, sha256: String, byteLength: Int)
  case modified(path: String, sha256: String, byteLength: Int)
  case deleted(path: String, sha256: String)
}

extension VaultObservation {
  var isCreate: Bool {
    if case .created = self {
      return true
    }
    return false
  }

  /// The NFC path relative to the vault root.
  public var path: String {
    switch self {
    case let .created(path, _, _), let .modified(path, _, _), let .deleted(path, _):
      path
    }
  }

  /// The SHA-256 of the bytes, for a delete the last bytes seen.
  public var sha256: String {
    switch self {
    case let .created(_, sha256, _), let .modified(_, sha256, _), let .deleted(_, sha256):
      sha256
    }
  }
}
