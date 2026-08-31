import Foundation

extension InboxWatchCoordinator {
  /// Replaces the registry projection without replacing the process runtime. Changed and removed
  /// targets relinquish their monitors; newly enabled targets begin watching immediately.
  public func replaceTargets(_ replacements: [WatchedFolderTarget]) async {
    let previous = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
    let next = Dictionary(uniqueKeysWithValues: replacements.map { ($0.id, $0) })
    let changed = Set(previous.keys.filter { next[$0] != previous[$0] })
    var retiredTasks: [Task<Void, Never>] = []
    for id in changed {
      monitors[id]?.stop()
      monitors.removeValue(forKey: id)
      states.removeValue(forKey: id)
      for (path, owner) in candidateFolders where owner == id {
        pendingPaths.remove(path)
        candidateFolders.removeValue(forKey: path)
        if let task = processingTasks[path] {
          task.cancel()
          retiredTasks.append(task)
        }
      }
      completedCandidates = completedCandidates.filter { $0.value.folderID != id }
    }
    for task in retiredTasks { await task.value }
    targets = replacements
    guard isWatching else { return }
    for target in replacements where target.isEnabled && (previous[target.id] != target) {
      activate(target)
    }
  }

  /// Performs one bounded full scan. Lifecycle wake and reachability hooks call this because
  /// filesystem timers and callbacks are not guaranteed to run while the Mac sleeps.
  public func reconcile() {
    runScanPass()
  }

  public func reminderObservations() -> [WatchedFolderReminderObservation] {
    targets.map { target in
      let items = candidateFolders.compactMap { path, folderID -> WatchedItemReminderObservation? in
        guard folderID == target.id, let snapshot = metadata.snapshot(ofItemAtPath: path) else {
          return nil
        }
        return WatchedItemReminderObservation(
          discoveredAt: snapshot.modifiedAt, isProcessed: completedCandidates[path] != nil
        )
      }
      return WatchedFolderReminderObservation(
        id: target.id, isEnabled: target.isEnabled, items: items
      )
    }
  }
}
