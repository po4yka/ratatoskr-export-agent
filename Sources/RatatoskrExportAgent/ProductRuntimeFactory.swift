import AgentCore
import Foundation

struct ProductRuntimeGraph: Sendable {
  let runtime: OperationalAgentRuntime
  let queue: UploadQueue
  let journal: LocalArchiveJournal
  let session: DeviceSessionCoordinator
  @MainActor let registry: WatchedFolderRegistry
  let watcher: InboxWatchCoordinator
  let processor: ArchiveCandidateProcessor

  @MainActor
  func refreshFolders() async {
    let folders = registry.runtimeFolders()
    await processor.replacePolicies(
      Dictionary(uniqueKeysWithValues: folders.map { ($0.target.id, $0.policy) })
    )
    await watcher.replaceTargets(folders.map(\.target))
  }
}

enum ProductRuntimeFactoryError: Error {
  case conflictingOrigins
}

@MainActor
enum ProductRuntimeFactory {
  static func make() async throws -> ProductRuntimeGraph {
    let support = try supportDirectory()
    let configuration = try AgentConfiguration.load(
      from: support.appending(path: "configuration.json"))
    let session = try await restoredSession(support: support, configuration: configuration)
    let journal = try LocalArchiveJournal.open(at: support.appending(path: "archive-journal.jsonl"))
    let registry = try makeRegistry(support: support)
    let folders = registry.runtimeFolders()
    let (watcher, processor) = makeWatcher(
      support: support, configuration: configuration, journal: journal, folders: folders
    )
    let archiveTransport = SessionBoundArchiveOperationTransport(session: session)
    let queue = UploadQueue(
      journal: journal, operationTransport: archiveTransport, configuration: configuration
    )
    let backend = makeBackend(journal: journal, session: session)
    let reminders = try makeReminders(support: support)
    let runtime = OperationalAgentRuntime(components: [
      InboxRuntimeComponent(watcher: watcher),
      UploadRuntimeComponent(queue: queue),
      backend,
      ReminderRuntimeComponent(watcher: watcher, reminders: reminders),
    ])
    return ProductRuntimeGraph(
      runtime: runtime, queue: queue, journal: journal, session: session,
      registry: registry, watcher: watcher, processor: processor
    )
  }

  private static func restoredSession(
    support: URL, configuration: AgentConfiguration
  ) async throws -> DeviceSessionCoordinator {
    let session = DeviceSessionCoordinator(
      transport: URLSessionPlatformDeviceTransport(),
      credentialStore: KeychainDeviceCredentialStore(),
      identityStore: FileDeviceIdentityStore(fileURL: support.appending(path: "paired-device.json"))
    )
    try await session.restore()
    if let configured = configuration.backendBaseURL,
      let paired = await session.pairedIdentity()?.origin, configured != paired
    {
      throw ProductRuntimeFactoryError.conflictingOrigins
    }
    return session
  }

  private static func makeWatcher(
    support: URL,
    configuration: AgentConfiguration,
    journal: LocalArchiveJournal,
    folders: [(target: WatchedFolderTarget, policy: FolderArchivePolicy)]
  ) -> (InboxWatchCoordinator, ArchiveCandidateProcessor) {
    let processor = ArchiveCandidateProcessor(
      store: LocalArchiveStore(
        root: support.appending(path: "archives"), maxStoreBytes: configuration.maxArchiveStoreBytes
      ),
      journal: journal,
      policies: Dictionary(uniqueKeysWithValues: folders.map { ($0.target.id, $0.policy) })
    )
    let watcher = InboxWatchCoordinator(
      targets: folders.map(\.target), monitorFactory: { FSEventsFolderMonitor(url: $0.url) },
      metadata: FileManagerMetadataProvider(), debounceScheduler: DispatchWatchScheduler(),
      tickScheduler: DispatchWatchScheduler(),
      configuration: CoordinatorConfiguration(
        debounceWindow: 0.5, quietInterval: 30, maxArchiveBytes: configuration.maxArchiveBytes
      ),
      clock: Date.init,
      onCandidate: { candidate in
        do {
          _ = try await processor.process(candidate)
          return true
        } catch {
          return false
        }
      }
    )
    return (watcher, processor)
  }

  private static func makeBackend(
    journal: LocalArchiveJournal, session: DeviceSessionCoordinator
  ) -> BackendImportRuntimeComponent {
    BackendImportRuntimeComponent(
      journal: journal,
      poller: BackendImportPollCoordinator(
        journal: journal, polling: SessionBoundBackendOperationPoller(session: session)
      ),
      notifications: ImportNotificationCoordinator(
        journal: journal, service: UserAgentNotificationService()
      )
    )
  }

  private static func makeReminders(
    support: URL
  ) throws -> WatchedItemReminderCoordinator {
    try WatchedItemReminderCoordinator(
      policy: WatchedItemReminderPolicy(threshold: 24 * 60 * 60),
      stateStore: FileWatchedItemReminderStateStore(
        fileURL: support.appending(path: "reminder-state.json")
      ),
      notificationService: UserAgentNotificationService()
    )
  }

  private static func supportDirectory() throws -> URL {
    let base =
      FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory
    let directory = base.appending(path: "Ratatoskr/ExportAgent", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private static func makeRegistry(support: URL) throws -> WatchedFolderRegistry {
    try WatchedFolderRegistry(
      preferencesStore: FileFolderPreferencesStore(
        fileURL: support.deletingLastPathComponent().appending(path: "folder-preferences.json")
      ),
      bookmarkStore: SecurityScopedBookmarkStore()
    )
  }
}
