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

/// What one ask of a rename check found. It gives the verdict of each hash
/// pair of one scan batch without asking again.
public struct VaultRenameAnswer: Sendable {
  /// The answer of a check that cannot answer.
  public static let unavailable = VaultRenameAnswer { _, _ in .unavailable }

  private let decide: @Sendable (_ oldPath: String, _ newPath: String) -> VaultRenameVerdict

  public init(_ decide: @escaping @Sendable (_ oldPath: String, _ newPath: String) -> VaultRenameVerdict) {
    self.decide = decide
  }

  public func verdict(renaming oldPath: String, to newPath: String) -> VaultRenameVerdict {
    decide(oldPath, newPath)
  }
}

/// A second opinion on a create and a delete with equal hashes. Only
/// `refuted` splits a pair, so a check that cannot answer changes nothing.
public protocol VaultRenameChecking: Sendable {
  /// Asks the check once for one scan batch. The vault mode calls it outside
  /// its lock, because a check can be slow.
  func answer() -> VaultRenameAnswer
}

/// The check to use when the Obsidian CLI is not configured.
public struct HashPairingOnly: VaultRenameChecking {
  public init() {}

  public func answer() -> VaultRenameAnswer {
    .unavailable
  }
}
