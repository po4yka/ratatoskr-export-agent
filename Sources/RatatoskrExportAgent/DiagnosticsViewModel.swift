import AgentCore
import SwiftUI

struct DiagnosticRow: Equatable, Identifiable {
  let title: String
  let value: String

  var id: String { title }
}

@MainActor
final class DiagnosticsViewModel: ObservableObject {
  @Published private(set) var snapshot: OperationalDiagnosticsSnapshot
  @Published private(set) var rows: [DiagnosticRow]

  init(snapshot: OperationalDiagnosticsSnapshot) {
    self.snapshot = snapshot
    rows = Self.makeRows(snapshot)
  }

  func replace(with snapshot: OperationalDiagnosticsSnapshot) {
    self.snapshot = snapshot
    rows = Self.makeRows(snapshot)
  }

  private static func makeRows(_ snapshot: OperationalDiagnosticsSnapshot) -> [DiagnosticRow] {
    [
      DiagnosticRow(title: "Folder access", value: folderAccessText(snapshot.folderPermissions)),
      DiagnosticRow(title: "Notifications", value: notificationText(snapshot.notifications)),
      DiagnosticRow(title: "Disk space", value: diskText(snapshot.diskSpace)),
      DiagnosticRow(title: "Journal", value: journalText(snapshot.journal)),
      DiagnosticRow(title: "Queue", value: queueText(snapshot.queue)),
      DiagnosticRow(title: "Updates", value: updateText(snapshot.updateCheck)),
    ]
  }

  private static func folderAccessText(_ value: FolderPermissionDiagnostics) -> String {
    guard value.isAvailable else { return "Unavailable" }
    return "\(value.accessible) accessible, \(value.needsReauthorization) need reauthorization, "
      + "\(value.missing) missing, \(value.denied) denied"
  }

  private static func notificationText(_ value: NotificationPermissionDiagnostics) -> String {
    value == .authorized ? "Authorized" : "Denied or unavailable"
  }

  private static func diskText(_ value: DiskSpaceDiagnostics) -> String {
    switch value {
    case .available(let bytes):
      ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " available"
    case .unavailable:
      "Unavailable"
    }
  }

  private static func journalText(_ value: JournalHealthDiagnostics) -> String {
    switch value {
    case .healthy(let entryCount):
      "Healthy, \(entryCount) entries"
    case .requiresAttention:
      "Requires attention"
    case .unavailable:
      "Unavailable"
    }
  }

  private static func queueText(_ value: QueueDepthDiagnostics) -> String {
    switch value {
    case .available(let queue):
      "\(queue.queued) queued, \(queue.active) active, \(queue.retrying) retrying, "
        + "\(queue.paused) paused, \(queue.failed) failed"
    case .unavailable:
      "Unavailable"
    }
  }

  private static func updateText(_ value: UpdateCheckDiagnostics) -> String {
    switch value {
    case .manualDownload(let currentVersion):
      guard let currentVersion else { return "Manual download; current version unavailable" }
      return "Manual download; current version \(currentVersion)"
    }
  }
}
