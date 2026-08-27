import AgentCore
import AppKit

/// Builds the status-bar menu and routes its items to the coordinator.
@MainActor
enum AgentMenu {
  static let settingsTitle = "Settings…"
  static let quitTitle = "Quit Ratatoskr"
  static let uploadStatusItemTag = 71

  /// Builds the menu items the agent exposes from its status item.
  static func make(coordinator: AgentMenuCoordinator, uploadStatus: UploadQueueStatus = .init(entries: [])) -> NSMenu {
    let menu = NSMenu()

    let statusItem = NSMenuItem(title: uploadStatus.menuTitle, action: nil, keyEquivalent: "")
    statusItem.tag = uploadStatusItemTag
    statusItem.isEnabled = false
    menu.addItem(statusItem)
    menu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: settingsTitle,
      action: #selector(AgentMenuCoordinator.settingsSelected),
      keyEquivalent: ","
    )
    settingsItem.target = coordinator
    menu.addItem(settingsItem)

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
