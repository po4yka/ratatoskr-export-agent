import Foundation

public struct FolderPermissionDiagnostics: Codable, Equatable, Sendable {
  public let isAvailable: Bool
  public let accessible: Int
  public let needsReauthorization: Int
  public let missing: Int
  public let denied: Int

  public init(
    accessible: Int,
    needsReauthorization: Int,
    missing: Int,
    denied: Int,
    isAvailable: Bool = true
  ) {
    self.isAvailable = isAvailable
    self.accessible = accessible
    self.needsReauthorization = needsReauthorization
    self.missing = missing
    self.denied = denied
  }
}

public enum NotificationPermissionDiagnostics: String, Codable, Sendable {
  case authorized
  case deniedOrUnavailable
}

public enum DiskSpaceDiagnostics: Codable, Equatable, Sendable {
  case available(bytes: Int64)
  case unavailable
}

public enum JournalHealthDiagnostics: Codable, Equatable, Sendable {
  case healthy(entryCount: Int)
  case requiresAttention
  case unavailable
}

public struct QueueDepthSummary: Codable, Equatable, Sendable {
  public let active: Int
  public let queued: Int
  public let paused: Int
  public let retrying: Int
  public let failed: Int

  public init(active: Int, queued: Int, paused: Int, retrying: Int, failed: Int) {
    self.active = active
    self.queued = queued
    self.paused = paused
    self.retrying = retrying
    self.failed = failed
  }
}

public enum QueueDepthDiagnostics: Codable, Equatable, Sendable {
  case available(QueueDepthSummary)
  case unavailable
}

public enum UpdateCheckDiagnostics: Codable, Equatable, Sendable {
  case manualDownload(currentVersion: String?)
}

public struct OperationalDiagnosticsSnapshot: Codable, Equatable, Sendable {
  public let folderPermissions: FolderPermissionDiagnostics
  public let notifications: NotificationPermissionDiagnostics
  public let diskSpace: DiskSpaceDiagnostics
  public let journal: JournalHealthDiagnostics
  public let queue: QueueDepthDiagnostics
  public let updateCheck: UpdateCheckDiagnostics

  public init(
    folderPermissions: FolderPermissionDiagnostics,
    notifications: NotificationPermissionDiagnostics,
    diskSpace: DiskSpaceDiagnostics,
    journal: JournalHealthDiagnostics,
    queue: QueueDepthDiagnostics,
    updateCheck: UpdateCheckDiagnostics
  ) {
    self.folderPermissions = folderPermissions
    self.notifications = notifications
    self.diskSpace = diskSpace
    self.journal = journal
    self.queue = queue
    self.updateCheck = updateCheck
  }
}

public enum OperationalDiagnosticsAssembler {
  public static func assemble(
    folderAccess: [FolderAccessState],
    notificationAuthorization: ImportNotificationAuthorization,
    diskSpace: DiskSpaceDiagnostics,
    journalHealth: JournalHealthDiagnostics,
    queueStatus: UploadQueueStatus?,
    folderAccessAvailable: Bool = true,
    applicationShortVersion: String? = nil
  ) -> OperationalDiagnosticsSnapshot {
    let permissions = folderAccess.reduce(
      into: FolderPermissionDiagnostics(accessible: 0, needsReauthorization: 0, missing: 0, denied: 0)
    ) { result, access in
      switch access {
      case .accessible:
        result = result.incrementing(accessible: 1)
      case .needsReauthorization:
        result = result.incrementing(needsReauthorization: 1)
      case .missing:
        result = result.incrementing(missing: 1)
      case .denied:
        result = result.incrementing(denied: 1)
      }
    }
    let notificationStatus: NotificationPermissionDiagnostics =
      notificationAuthorization == .authorized ? .authorized : .deniedOrUnavailable
    let queue = trustedQueue(journalHealth: journalHealth, status: queueStatus)
    let permissionState = FolderPermissionDiagnostics(
      accessible: permissions.accessible,
      needsReauthorization: permissions.needsReauthorization,
      missing: permissions.missing,
      denied: permissions.denied,
      isAvailable: folderAccessAvailable
    )
    return OperationalDiagnosticsSnapshot(
      folderPermissions: permissionState,
      notifications: notificationStatus,
      diskSpace: diskSpace,
      journal: journalHealth,
      queue: queue,
      updateCheck: ApplicationUpdatePolicy.diagnostics(currentVersion: applicationShortVersion)
    )
  }

  private static func trustedQueue(
    journalHealth: JournalHealthDiagnostics,
    status: UploadQueueStatus?
  ) -> QueueDepthDiagnostics {
    guard case .healthy = journalHealth, let status else { return .unavailable }
    return .available(
      QueueDepthSummary(
        active: status.activeCount,
        queued: status.queuedCount,
        paused: status.pausedCount,
        retrying: status.retryingCount,
        failed: status.failedCount
      )
    )
  }
}

private extension FolderPermissionDiagnostics {
  func incrementing(
    accessible: Int = 0,
    needsReauthorization: Int = 0,
    missing: Int = 0,
    denied: Int = 0
  ) -> FolderPermissionDiagnostics {
    FolderPermissionDiagnostics(
      accessible: self.accessible + accessible,
      needsReauthorization: self.needsReauthorization + needsReauthorization,
      missing: self.missing + missing,
      denied: self.denied + denied
    )
  }
}
