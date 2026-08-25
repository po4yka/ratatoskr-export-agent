import Foundation

/// Why an inbox path was refused as a candidate instead of being queued.
public enum CandidateRejection: Equatable, Sendable {
  /// The path is not a regular file (directory, symlink, device, other).
  case notRegularFile

  /// The agent cannot read the file's contents.
  case unreadable

  /// The file is larger than the configured ceiling.
  case exceedsSizeLimit(limitBytes: Int)

  /// The name carries a temporary download suffix; not final content yet.
  case temporarySuffix
}

/// Admission rules checked before any stability waiting: only regular,
/// readable files within the configured size ceiling may become candidates.
public struct CandidateEligibilityGate: Sendable {
  private let maxArchiveBytes: Int

  public init(maxArchiveBytes: Int) {
    self.maxArchiveBytes = maxArchiveBytes
  }

  /// Returns the rejection reason for these facts, or nil when eligible.
  public func rejection(
    isRegularFile: Bool,
    isReadable: Bool,
    byteSize: Int
  ) -> CandidateRejection? {
    guard isRegularFile else {
      return .notRegularFile
    }
    guard isReadable else {
      return .unreadable
    }
    guard byteSize <= maxArchiveBytes else {
      return .exceedsSizeLimit(limitBytes: maxArchiveBytes)
    }
    return nil
  }
}
