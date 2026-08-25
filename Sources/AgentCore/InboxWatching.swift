import Foundation

/// One folder handed to the watcher: registry identity plus resolved
/// location and participation flag.
public struct WatchedFolderTarget: Equatable, Sendable {
  /// Registry identity of the folder.
  public var id: UUID

  /// Resolved location of the folder's directory.
  public var url: URL

  /// Whether the folder participates in watching.
  public var isEnabled: Bool

  public init(id: UUID, url: URL, isEnabled: Bool) {
    self.id = id
    self.url = url
    self.isEnabled = isEnabled
  }
}

/// Why a watched folder stopped being observable.
public enum FolderDegradationReason: Equatable, Sendable {
  /// Nothing exists at the folder location any more.
  case missing

  /// Listing the folder's contents was refused.
  case unreadable

  /// The platform-level monitor could not be created or started.
  case monitorFailed
}

/// Per-folder observation health surfaced by the coordinator.
public enum FolderWatchState: Equatable, Sendable {
  /// Events and candidates flow for this folder.
  case watching

  /// This folder alone is degraded; other folders continue.
  case degraded(FolderDegradationReason)
}

/// A candidate whose stability evidence completed: safe to hand to the next
/// pipeline stage (hashing/journal/upload land in their own changes).
public struct StableArchiveCandidate: Equatable, Sendable {
  /// Registry identity of the folder the archive came from.
  public var folderID: UUID

  /// Location of the stable archive file.
  public var url: URL

  /// The snapshot that held still across the quiet interval.
  public var snapshot: FileSnapshot

  /// The quiet-period evidence behind the verdict.
  public var evidence: StabilityEvidence

  public init(
    folderID: UUID,
    url: URL,
    snapshot: FileSnapshot,
    evidence: StabilityEvidence
  ) {
    self.folderID = folderID
    self.url = url
    self.snapshot = snapshot
    self.evidence = evidence
  }
}

/// Platform-level observation of one folder's activity. Implementations
/// report only that something happened; scans remain authoritative.
public protocol InboxFolderMonitoring: AnyObject, Sendable {
  /// Begins observation, invoking the handler on later activity. Throws
  /// instead of starting a dead stream when the folder cannot be observed.
  func start(onActivity: @escaping @Sendable () -> Void) throws

  /// Ends observation; safe to call repeatedly.
  func stop()
}

/// Tunables for inbox watching; documented defaults keep behaviour sane
/// without configuration plumbing.
public struct CoordinatorConfiguration: Sendable {
  /// Window collapsing event bursts into one scan.
  public var debounceWindow: TimeInterval

  /// Quiet period a file must survive before queueing.
  public var quietInterval: TimeInterval

  /// Size ceiling applied to candidates.
  public var maxArchiveBytes: Int

  public static let defaultValue = CoordinatorConfiguration(
    debounceWindow: 0.5,
    quietInterval: 30,
    maxArchiveBytes: 2 * 1024 * 1024 * 1024
  )

  public init(
    debounceWindow: TimeInterval,
    quietInterval: TimeInterval,
    maxArchiveBytes: Int
  ) {
    self.debounceWindow = debounceWindow
    self.quietInterval = quietInterval
    self.maxArchiveBytes = maxArchiveBytes
  }
}
