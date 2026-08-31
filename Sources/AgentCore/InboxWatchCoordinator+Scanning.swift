import Foundation

// Scan, diff, and degradation internals for InboxWatchCoordinator. This
// extension exists to honour the file- and type-length ceilings; the members
// it shares with the actor are internal rather than private for that reason
// only.
extension InboxWatchCoordinator {
  /// Registers a platform monitor for an enabled folder; a failure to
  /// create or start degrades only that folder.
  func activate(_ target: WatchedFolderTarget) {
    do {
      let monitor = try makeMonitor(target)
      monitors[target.id] = monitor
      states[target.id] = .watching
      try monitor.start { [weak self] in
        guard let self else {
          return
        }
        Task { await self.folderHadActivity() }
      }
    } catch {
      states[target.id] = .degraded(.monitorFailed)
    }
  }

  /// Entry point for platform monitor callbacks announcing folder activity.
  /// Internal so tests can drive it without kernel event timing.
  func folderHadActivity() {
    guard isWatching else {
      return
    }
    debouncer?.trigger { [weak self] in
      guard let self else {
        return
      }
      Task { await self.runScanPass() }
    }
  }

  /// Lists one watched folder and reconciles its contents against tracked
  /// candidates. A missing or unreadable folder degrades alone.
  func scan(folderID: UUID) {
    guard states[folderID] == .watching,
      let target = targets.first(where: { $0.id == folderID })
    else {
      return
    }
    do {
      let entries = try metadata.contentsOfDirectory(at: target.url)
      ingest(entries: entries, folderID: folderID)
    } catch {
      degrade(folderID: folderID, reason: Self.degradationReason(for: error))
    }
  }

  /// Re-assesses every pending candidate path once.
  func reassessPendingPaths() {
    for path in pendingPaths.sorted() {
      guard let folderID = candidateFolders[path] else {
        pendingPaths.remove(path)
        continue
      }
      apply(tracker?.assess(path: path) ?? .pending, path: path, folderID: folderID)
    }
  }

  private func ingest(entries: [URL], folderID: UUID) {
    for entry in entries {
      let path = entry.path
      guard completedCandidates[path] == nil else {
        continue
      }
      let assessment = tracker?.assess(path: path) ?? .pending
      if case .pending = assessment {
        pendingPaths.insert(path)
        candidateFolders[path] = folderID
      }
      apply(assessment, path: path, folderID: folderID)
    }
  }

  /// Applies one assessment outcome: queueing stable candidates exactly
  /// once per path and dropping refusals from the pending set.
  private func apply(_ assessment: CandidateAssessment, path: String, folderID: UUID) {
    switch assessment {
    case .pending:
      break
    case .stable(let stable):
      deliver(
        StableArchiveCandidate(
          folderID: folderID,
          url: stable.url,
          snapshot: stable.snapshot,
          evidence: stable.evidence
        ),
        path: path
      )
    case .rejected:
      pendingPaths.remove(path)
      candidateFolders.removeValue(forKey: path)
    }
  }

  private func deliver(_ candidate: StableArchiveCandidate, path: String) {
    guard processingTasks[path] == nil else { return }
    let handler = onCandidate
    processingTasks[path] = Task { [weak self] in
      let succeeded = await handler(candidate)
      await self?.finishProcessing(candidate, path: path, succeeded: succeeded)
    }
  }

  private func finishProcessing(
    _ candidate: StableArchiveCandidate,
    path: String,
    succeeded: Bool
  ) {
    processingTasks.removeValue(forKey: path)
    guard isWatching, candidateFolders[path] == candidate.folderID else { return }
    if succeeded {
      completedCandidates[path] = candidate
      pendingPaths.remove(path)
      candidateFolders.removeValue(forKey: path)
    } else {
      scheduleNextReassessmentIfNecessary()
    }
  }

  /// Stops observing one degraded folder and forgets its pending
  /// candidates; other folders continue untouched.
  private func degrade(folderID: UUID, reason: FolderDegradationReason) {
    states[folderID] = .degraded(reason)
    monitors[folderID]?.stop()
    monitors.removeValue(forKey: folderID)
    for (path, owner) in candidateFolders where owner == folderID {
      pendingPaths.remove(path)
      candidateFolders.removeValue(forKey: path)
    }
  }

  private static func degradationReason(for error: Error) -> FolderDegradationReason {
    switch (error as? CocoaError)?.code {
    case .fileNoSuchFile, .fileReadNoSuchFile:
      .missing
    default:
      .unreadable
    }
  }
}
