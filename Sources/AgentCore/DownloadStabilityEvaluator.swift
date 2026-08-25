import Foundation

/// One observed state of an inbox file: byte size and modification time.
public struct FileSnapshot: Equatable, Sendable {
  /// Size in bytes at observation time.
  public var byteSize: Int

  /// Modification timestamp at observation time.
  public var modifiedAt: Date

  public init(byteSize: Int, modifiedAt: Date) {
    self.byteSize = byteSize
    self.modifiedAt = modifiedAt
  }
}

/// Evidence recorded when a candidate is judged stable.
public struct StabilityEvidence: Equatable, Sendable {
  /// How long the file stayed unchanged before being declared stable.
  public var quietDuration: TimeInterval

  /// The snapshot that held still across the quiet interval.
  public var snapshot: FileSnapshot

  public init(quietDuration: TimeInterval, snapshot: FileSnapshot) {
    self.quietDuration = quietDuration
    self.snapshot = snapshot
  }
}

/// The local stability verdict for one candidate path.
public enum CandidateStability: Equatable, Sendable {
  /// Not yet eligible; keep observing.
  case pending

  /// Quiet evidence complete; safe to queue for the next pipeline stage.
  case stable(StabilityEvidence)
}

/// Decides from observations alone whether a file has finished downloading:
/// its size and modification time must hold still across a configured quiet
/// interval. Pure logic; time enters as parameters so tests stay exact.
public struct DownloadStabilityEvaluator: Sendable {
  private let quietInterval: TimeInterval

  public init(quietInterval: TimeInterval) {
    self.quietInterval = quietInterval
  }

  /// Evaluates one observation against the baseline (first sight or last
  /// change). A differing current snapshot reports pending; the caller is
  /// expected to adopt it as the new baseline.
  public func evaluate(
    baselineSnapshot: FileSnapshot,
    baselineSince: Date,
    current: FileSnapshot,
    now: Date,
    writerHoldDetected: Bool
  ) -> CandidateStability {
    guard current == baselineSnapshot else {
      return .pending
    }
    let quietSeconds = now.timeIntervalSince(baselineSince)
    guard quietSeconds >= quietInterval, !writerHoldDetected else {
      return .pending
    }
    return .stable(StabilityEvidence(quietDuration: quietSeconds, snapshot: current))
  }
}
