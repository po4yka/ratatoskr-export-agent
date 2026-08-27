import AgentCore
import Foundation

struct DiagnosticsSnapshotContext {
  let snapshot: OperationalDiagnosticsSnapshot
  let entries: [JournalEntry]
}

@MainActor
enum DiagnosticsSnapshotLoader {
  static func load(
    notificationAuthorization: ImportNotificationAuthorization
  ) -> OperationalDiagnosticsSnapshot {
    loadContext(notificationAuthorization: notificationAuthorization).snapshot
  }

  static func loadContext(
    notificationAuthorization: ImportNotificationAuthorization
  ) -> DiagnosticsSnapshotContext {
    let directory = applicationSupportDirectory()
    let registry = try? WatchedFolderRegistry(
      preferencesStore: FileFolderPreferencesStore(
        fileURL: directory.appendingPathComponent("folder-preferences.json")
      ),
      bookmarkStore: SecurityScopedBookmarkStore()
    )
    let folderAccess = registry?.folders.map { registry?.accessState(for: $0.id) ?? .denied } ?? []
    let journalContext = journalDiagnostics(
      at: directory.appendingPathComponent("archive-journal.ndjson")
    )
    let snapshot = OperationalDiagnosticsAssembler.assemble(
      folderAccess: folderAccess,
      notificationAuthorization: notificationAuthorization,
      diskSpace: FileManagerDiskSpaceProbe().availableSpace(at: directory),
      journalHealth: journalContext.diagnostics.health,
      queueStatus: journalContext.diagnostics.queueStatus,
      folderAccessAvailable: registry != nil
    )
    return DiagnosticsSnapshotContext(snapshot: snapshot, entries: journalContext.entries)
  }

  private static func journalDiagnostics(
    at url: URL
  ) -> (diagnostics: LocalJournalDiagnostics, entries: [JournalEntry]) {
    do {
      let journal = try LocalArchiveJournal.open(at: url)
      return (LocalJournalDiagnostics(open: journal), journal.entries)
    } catch {
      return (LocalJournalDiagnostics(openFailure: error), [])
    }
  }

  private static func applicationSupportDirectory() -> URL {
    let root = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    let directory = root.appendingPathComponent("Ratatoskr", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
