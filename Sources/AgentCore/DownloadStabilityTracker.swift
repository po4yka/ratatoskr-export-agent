import Foundation

/// Tracks per-path quiet-period state across repeated assessments of a
/// watched folder's contents, turning single observations into stability
/// verdicts: eligibility gates first, temporary-suffix exclusion next,
/// then the quiet-interval decision.
public struct DownloadStabilityTracker: Sendable {
  /// One candidate's local lifecycle: first sight through terminal outcome.
  private enum Cycle {
    case evaluating(snapshot: FileSnapshot, since: Date)
    case completed(StableCandidate)
  }

  private let metadata: any FileMetadataProviding
  private let evaluator: DownloadStabilityEvaluator
  private let gate: CandidateEligibilityGate
  private let now: @Sendable () -> Date
  private var cycles: [String: Cycle] = [:]

  public init(
    metadata: any FileMetadataProviding,
    evaluator: DownloadStabilityEvaluator,
    gate: CandidateEligibilityGate,
    now: @escaping @Sendable () -> Date
  ) {
    self.metadata = metadata
    self.evaluator = evaluator
    self.gate = gate
    self.now = now
  }

  /// Assesses one path afresh, carrying forward its quiet-period baseline.
  public mutating func assess(path: String) -> CandidateAssessment {
    let observedAt = now()
    guard let current = metadata.snapshot(ofItemAtPath: path) else {
      cycles.removeValue(forKey: path)
      return .pending
    }
    if let rejection = gate.rejection(
      isRegularFile: metadata.isRegularFile(atPath: path),
      isReadable: metadata.isReadableFile(atPath: path),
      byteSize: current.byteSize
    ) {
      return .rejected(rejection)
    }
    if PartialDownloadHeuristics.hasTemporarySuffix((path as NSString).lastPathComponent) {
      return .rejected(.temporarySuffix)
    }
    return assessTracked(path: path, current: current, observedAt: observedAt)
  }

  // MARK: - Cycle handling

  private mutating func assessTracked(
    path: String, current: FileSnapshot, observedAt: Date
  ) -> CandidateAssessment {
    switch cycles[path] {
    case .completed(let candidate):
      guard candidate.snapshot == current else {
        cycles[path] = .evaluating(snapshot: current, since: observedAt)
        return .pending
      }
      return .stable(candidate)
    case .evaluating(let baseline, let since):
      return advanceEvaluating(
        path: path, baseline: baseline, since: since, current: current, observedAt: observedAt)
    case nil:
      cycles[path] = .evaluating(snapshot: current, since: observedAt)
      return .pending
    }
  }

  private mutating func advanceEvaluating(
    path: String,
    baseline: FileSnapshot,
    since: Date,
    current: FileSnapshot,
    observedAt: Date
  ) -> CandidateAssessment {
    let verdict = evaluator.evaluate(
      baselineSnapshot: baseline,
      baselineSince: since,
      current: current,
      now: observedAt,
      writerHoldDetected: metadata.writerHoldDetected(atPath: path)
    )
    switch verdict {
    case .stable(let evidence):
      let candidate = StableCandidate(
        url: URL(fileURLWithPath: path),
        snapshot: current,
        evidence: evidence
      )
      cycles[path] = .completed(candidate)
      return .stable(candidate)
    case .pending:
      if current != baseline {
        cycles[path] = .evaluating(snapshot: current, since: observedAt)
      }
      return .pending
    }
  }
}
