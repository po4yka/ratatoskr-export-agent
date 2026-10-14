import Foundation

/// One file system fact about a vault file, after the agent read the disk.
public enum VaultObservation: Equatable, Sendable {
  case created(path: String, sha256: String, byteLength: Int)
  case modified(path: String, sha256: String, byteLength: Int)
  case deleted(path: String, sha256: String)
}

/// Turns vault observations into the ordered changes of a batch.
public struct VaultWatcher: Sendable {
  public init(firstSequence: UInt64) {}

  /// Records one observation at the time the agent made it.
  public mutating func record(_ observation: VaultObservation, at time: Date) {}

  /// Returns the changes that are final at `time`.
  public mutating func drain(at time: Date) -> [VaultChange] {
    []
  }
}
