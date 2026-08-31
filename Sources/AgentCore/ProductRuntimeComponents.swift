import Foundation

public struct InboxRuntimeComponent: OperationalRuntimeComponent {
  private let watcher: InboxWatchCoordinator

  public init(watcher: InboxWatchCoordinator) { self.watcher = watcher }
  public func start() async { await watcher.start() }
  public func reconcile() async { await watcher.reconcile() }
  public func stop() async { await watcher.stop() }
}

public struct UploadRuntimeComponent: OperationalRuntimeComponent {
  private let queue: UploadQueue

  public init(queue: UploadQueue) { self.queue = queue }
  public func start() async {}
  public func reconcile() async { _ = await queue.runEligible() }
  public func stop() async {}
}

public struct ReminderRuntimeComponent: OperationalRuntimeComponent {
  private let watcher: InboxWatchCoordinator
  private let reminders: WatchedItemReminderCoordinator

  public init(
    watcher: InboxWatchCoordinator,
    reminders: WatchedItemReminderCoordinator
  ) {
    self.watcher = watcher
    self.reminders = reminders
  }

  public func start() async {}
  public func reconcile() async {
    let observations = await watcher.reminderObservations()
    _ = try? await reminders.evaluate(observations, at: Date())
  }
  public func stop() async {}
}

public final class BackendImportRuntimeComponent: OperationalRuntimeComponent, @unchecked Sendable {
  private let journal: LocalArchiveJournal
  private let poller: BackendImportPollCoordinator
  private let notifications: ImportNotificationCoordinator

  public init(
    journal: LocalArchiveJournal,
    poller: BackendImportPollCoordinator,
    notifications: ImportNotificationCoordinator
  ) {
    self.journal = journal
    self.poller = poller
    self.notifications = notifications
  }

  public func start() async {}

  public func reconcile() async {
    let candidates = journal.entries.filter {
      $0.operationID != nil && $0.state == .uploaded
        && $0.backendImport?.presentation.isTerminal != true
    }
    for entry in candidates {
      if let updated = await poller.refresh(entryID: entry.id),
        updated.backendImport?.presentation.isTerminal == true
      {
        _ = await notifications.notifyIfNeeded(entryID: entry.id)
        if updated.state == .uploaded {
          _ = try? journal.advance(entryID: entry.id, to: .confirmed)
        }
      }
    }
  }

  public func stop() async {}
}
