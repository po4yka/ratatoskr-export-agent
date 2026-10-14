import Foundation

/// The answer of a rename check for one hash pair.
public enum VaultRenameVerdict: Equatable, Sendable {
  /// The check agrees that the old path moved to the new path.
  case confirmed

  /// The check knows that the pair is not a rename.
  case refuted

  /// The check cannot answer. The hash pairing decides.
  case unavailable
}

/// A second opinion on a create and a delete with equal hashes. Only
/// `refuted` splits a pair, so a check that cannot answer changes nothing.
public protocol VaultRenameChecking: Sendable {
  func verdict(renaming oldPath: String, to newPath: String) -> VaultRenameVerdict
}

/// The check to use when the Obsidian CLI is not configured.
public struct HashPairingOnly: VaultRenameChecking {
  public init() {}

  public func verdict(renaming oldPath: String, to newPath: String) -> VaultRenameVerdict {
    .unavailable
  }
}
