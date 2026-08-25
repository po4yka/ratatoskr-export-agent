import Foundation

/// Read-only filesystem facts about one inbox path, so detection logic can
/// be tested against fixtures instead of live filesystem state.
public protocol FileMetadataProviding: Sendable {
  /// The observed size and modification time, or nil when the path does not
  /// exist or cannot be inspected.
  func snapshot(ofItemAtPath path: String) -> FileSnapshot?

  /// Whether the path is a regular file (not directory/symlink/special).
  func isRegularFile(atPath path: String) -> Bool

  /// Whether the agent can read the file's contents.
  func isReadableFile(atPath path: String) -> Bool

  /// Where detectable: whether another writer currently holds the file open
  /// for writing. A false result is advisory, never proof of no-writer.
  func writerHoldDetected(atPath path: String) -> Bool

  /// Lists a directory's immediate entries, or throws when the directory
  /// is missing or cannot be read.
  func contentsOfDirectory(at url: URL) throws -> [URL]
}

/// One candidate judged stable: what it is and the evidence that cleared it.
public struct StableCandidate: Equatable, Sendable {
  /// Location of the stable file inside its watched folder.
  public var url: URL

  /// The snapshot that held still across the quiet interval.
  public var snapshot: FileSnapshot

  /// The quiet-period evidence behind the verdict.
  public var evidence: StabilityEvidence

  public init(url: URL, snapshot: FileSnapshot, evidence: StabilityEvidence) {
    self.url = url
    self.snapshot = snapshot
    self.evidence = evidence
  }
}

/// The full local assessment for one candidate path, including refusals.
public enum CandidateAssessment: Equatable, Sendable {
  /// Not yet eligible; keep observing.
  case pending

  /// Safe to queue for the next pipeline stage.
  case stable(StableCandidate)

  /// Refused with the recorded reason; never queued while refused.
  case rejected(CandidateRejection)
}
