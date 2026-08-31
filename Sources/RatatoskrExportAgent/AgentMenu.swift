import AgentCore
import AppKit

/// Builds the status-bar menu and routes its items to the coordinator.
@MainActor
enum AgentMenu {
  static let settingsTitle = "Settings…"
  static let diagnosticsTitle = "Diagnostics…"
  static let checkForUpdatesTitle = "Check for Updates…"
  static let quitTitle = "Quit Ratatoskr"
  static let uploadStatusItemTag = 71
  static let importStatusItemTag = 72
  static let uploadControlsItemTag = 73

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
    addUploadControls(status: uploadStatus, coordinator: coordinator, to: menu)
    addImportStatus(entries: importEntries, to: menu)
    menu.addItem(.separator())

    menu.addItem(
      actionItem(
        title: settingsTitle,
        action: #selector(AgentMenuCoordinator.settingsSelected),
        keyEquivalent: ",",
        target: coordinator
      ))

    menu.addItem(
      actionItem(
        title: diagnosticsTitle,
        action: #selector(AgentMenuCoordinator.diagnosticsSelected),
        target: coordinator
      ))

    menu.addItem(
      actionItem(
        title: checkForUpdatesTitle,
        action: #selector(AgentMenuCoordinator.checkForUpdatesSelected),
        target: coordinator
      ))

    menu.addItem(.separator())

    menu.addItem(
      actionItem(
        title: quitTitle,
        action: #selector(AgentMenuCoordinator.quitSelected),
        keyEquivalent: "q",
        target: coordinator
      ))

    return menu
  }

  /// Applies a queue-owned, privacy-safe projection to an existing menu.
  static func apply(uploadStatus: UploadQueueStatus, to menu: NSMenu) {
    menu.items.first(where: { $0.tag == uploadStatusItemTag })?.title = uploadStatus.menuTitle
    menu.items.filter { $0.tag == uploadControlsItemTag }.forEach(menu.removeItem)
    guard let coordinator = menu.items.compactMap({ $0.target as? AgentMenuCoordinator }).first
    else {
      return
    }
    let insertion = menu.items.firstIndex(where: { $0.isSeparatorItem }) ?? menu.items.count
    if let item = uploadControls(status: uploadStatus, coordinator: coordinator) {
      menu.insertItem(item, at: insertion)
    }
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

  private static func actionItem(
    title: String,
    action: Selector,
    keyEquivalent: String = "",
    target: AnyObject
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = target
    return item
  }
}
