import Foundation

/// Orchestrates folder observation, debounced scans, and stability
/// detection over the enabled watched folders, delivering stable
/// candidates to its consumer exactly once per path.
public actor InboxWatchCoordinator {
  /// Creates a platform monitor for one folder target.
  public typealias MonitorFactory =
    @Sendable (WatchedFolderTarget) throws ->
    any InboxFolderMonitoring

  let targets: [WatchedFolderTarget]
  let makeMonitor: MonitorFactory
  private let debounceScheduler: any WatchScheduling
  private let tickScheduler: any WatchScheduling
  private let configuration: CoordinatorConfiguration
  private let clock: @Sendable () -> Date
  private let onScanPassFinished: @Sendable () -> Void

  // Scan/diff/degrade/activate internals live in
  // InboxWatchCoordinator+Scanning.swift; the split exists only to honour
  // the file- and type-length ceilings, so members they touch are internal
  // rather than private.
  var tracker: DownloadStabilityTracker?
  let metadata: any FileMetadataProviding
  var monitors: [UUID: any InboxFolderMonitoring] = [:]
  var states: [UUID: FolderWatchState] = [:]
  var pendingPaths: Set<String> = []
  var candidateFolders: [String: UUID] = [:]
  var completedCandidates: [String: StableArchiveCandidate] = [:]
  var reassessmentScheduled = false
  var isWatching = false
  var debouncer: Debouncer?
  let onCandidate: @Sendable (StableArchiveCandidate) -> Void

  /// Diagnostic hook invoked after every scan pass completes; used by
  /// health surfaces (and tests) to observe pass boundaries deterministically.
  public init(
    targets: [WatchedFolderTarget],
    monitorFactory: @escaping MonitorFactory,
    metadata: any FileMetadataProviding,
    debounceScheduler: any WatchScheduling,
    tickScheduler: any WatchScheduling,
    configuration: CoordinatorConfiguration,
    clock: @escaping @Sendable () -> Date,
    onCandidate: @escaping @Sendable (StableArchiveCandidate) -> Void,
    onScanPassFinished: @escaping @Sendable () -> Void = {}
  ) {
    self.targets = targets
    self.makeMonitor = monitorFactory
    self.metadata = metadata
    self.debounceScheduler = debounceScheduler
    self.tickScheduler = tickScheduler
    self.configuration = configuration
    self.clock = clock
    self.onCandidate = onCandidate
    self.onScanPassFinished = onScanPassFinished
  }

  /// Begins watching the enabled folders and performs the initial scan.
  /// A folder whose monitor cannot start degrades alone.
  public func start() {
    guard !isWatching else {
      return
    }
    isWatching = true
    tracker = DownloadStabilityTracker(
      metadata: metadata,
      evaluator: DownloadStabilityEvaluator(quietInterval: configuration.quietInterval),
      gate: CandidateEligibilityGate(maxArchiveBytes: configuration.maxArchiveBytes),
      now: clock
    )
    debouncer = Debouncer(
      window: configuration.debounceWindow,
      scheduler: debounceScheduler,
      now: clock
    )
    for target in targets where target.isEnabled {
      activate(target)
    }
    runScanPass()
  }

  /// Ends all observation; safe to call repeatedly.
  public func stop() {
    guard isWatching else {
      return
    }
    isWatching = false
    for monitor in monitors.values {
      monitor.stop()
    }
    monitors.removeAll()
    states.removeAll()
    pendingPaths.removeAll()
    candidateFolders.removeAll()
    completedCandidates.removeAll()
    reassessmentScheduled = false
    debounceScheduler.cancelScheduledWork()
    tickScheduler.cancelScheduledWork()
  }

  /// The current observation state for one folder, if it is a target.
  public func status(for id: UUID) -> FolderWatchState? {
    states[id]
  }

  /// Runs one full scan pass and schedules the next reassessment while
  /// candidates remain pending.
  func runScanPass() {
    guard isWatching else {
      return
    }
    for id in monitors.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
      scan(folderID: id)
    }
    reassessPendingPaths()
    scheduleNextReassessmentIfNecessary()
    onScanPassFinished()
  }

  func runScanPassFromTimer() {
    reassessmentScheduled = false
    runScanPass()
  }

  private func scheduleNextReassessmentIfNecessary() {
    guard !pendingPaths.isEmpty, isWatching, !reassessmentScheduled else {
      return
    }
    reassessmentScheduled = true
    tickScheduler.scheduleWork(
      deadline: clock().addingTimeInterval(configuration.quietInterval)
    ) { [weak self] in
      guard let self else {
        return
      }
      Task { await self.runScanPassFromTimer() }
    }
  }
}
