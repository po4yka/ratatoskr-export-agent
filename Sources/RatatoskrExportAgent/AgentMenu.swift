import AgentCore
import AppKit

/// Builds the status-bar menu and routes its items to the coordinator.
@MainActor
enum AgentMenu {
  static let settingsTitle = "Settings…"
  static let diagnosticsTitle = "Diagnostics…"
  static let quitTitle = "Quit Ratatoskr"
  static let uploadStatusItemTag = 71
  static let importStatusItemTag = 72

  /// Builds the menu items the agent exposes from its status item.
  static func make(
    coordinator: AgentMenuCoordinator,
    uploadStatus: UploadQueueStatus = .init(entries: []),
    importEntries: [JournalEntry] = []
  ) -> NSMenu {
    let menu = NSMenu()

    let statusItem = NSMenuItem(title: uploadStatus.menuTitle, action: nil, keyEquivalent: "")
    statusItem.tag = uploadStatusItemTag
    statusItem.isEnabled = false
    menu.addItem(statusItem)
    addImportStatus(entries: importEntries, to: menu)
    menu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: settingsTitle,
      action: #selector(AgentMenuCoordinator.settingsSelected),
      keyEquivalent: ","
    )
    settingsItem.target = coordinator
    menu.addItem(settingsItem)

    let diagnosticsItem = NSMenuItem(
      title: diagnosticsTitle,
      action: #selector(AgentMenuCoordinator.diagnosticsSelected),
      keyEquivalent: ""
    )
    diagnosticsItem.target = coordinator
    menu.addItem(diagnosticsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: quitTitle,
      action: #selector(AgentMenuCoordinator.quitSelected),
      keyEquivalent: "q"
    )
    quitItem.target = coordinator
    menu.addItem(quitItem)

    return menu
  }

  /// Applies a queue-owned, privacy-safe projection to an existing menu.
  static func apply(uploadStatus: UploadQueueStatus, to menu: NSMenu) {
    menu.items.first(where: { $0.tag == uploadStatusItemTag })?.title = uploadStatus.menuTitle
  }

  /// Replaces only the immutable status rows; AppKit never receives authority to mutate a journal.
  static func apply(importEntries: [JournalEntry], to menu: NSMenu) {
    menu.items.filter { $0.tag == importStatusItemTag }.forEach(menu.removeItem)
    let insertion = menu.items.firstIndex(where: { $0.isSeparatorItem }) ?? menu.items.count
    let rows = ImportStatusMenuProjection.titles(entries: importEntries).map { title in
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.tag = importStatusItemTag
      item.isEnabled = false
      return item
    }
    for (offset, row) in rows.enumerated() {
      menu.insertItem(row, at: insertion + offset)
    }
  }

  private static func addImportStatus(entries: [JournalEntry], to menu: NSMenu) {
    for title in ImportStatusMenuProjection.titles(entries: entries) {
      let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      item.tag = importStatusItemTag
      item.isEnabled = false
      menu.addItem(item)
    }
  }
}

/// Binds menu rendering to queue-owned state without giving AppKit authority
/// to mutate uploads, files, or transport state.
@MainActor
final class UploadMenuStatusBinding {
  private var updateTask: Task<Void, Never>?

  init(menu: NSMenu, updates: AsyncStream<UploadQueueStatus>) {
    updateTask = Task { [weak menu] in
      for await status in updates {
        guard let menu else { return }
        AgentMenu.apply(uploadStatus: status, to: menu)
      }
    }
  }

  deinit {
    updateTask?.cancel()
  }
}

/// Handles status-bar menu selections.
@MainActor
final class AgentMenuCoordinator: NSObject {
  private var settingsWindowController: SettingsWindowController?
  private var diagnosticsWindowController: DiagnosticsWindowController?

  @objc
  func diagnosticsSelected() {
    if diagnosticsWindowController == nil {
      diagnosticsWindowController = DiagnosticsWindowController.makeDefault()
    }
    diagnosticsWindowController?.showDiagnostics()
  }

  @objc
  func settingsSelected() {
    if settingsWindowController == nil {
      guard let controller = SettingsWindowController.makeDefault() else {
        presentLoadFailure()
        return
      }
      settingsWindowController = controller
    }
    settingsWindowController?.showSettings()
  }

  @objc
  func quitSelected() {
    NSApplication.shared.terminate(nil)
  }

  /// Surfaces an unreadable preferences document as an actionable dialog;
  /// the message carries no filesystem detail.
  private func presentLoadFailure() {
    let alert = NSAlert()
    alert.messageText = "Watched folder settings could not be loaded."
    alert.informativeText =
      "The stored settings document is invalid. Repair or remove it, then reopen Settings."
    alert.alertStyle = .warning
    alert.runModal()
  }
}
