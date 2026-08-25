import AppKit

/// Builds the status-bar menu and routes its items to the coordinator.
@MainActor
enum AgentMenu {
  static let settingsTitle = "Settings…"
  static let quitTitle = "Quit Ratatoskr"

  /// Builds the menu items the agent exposes from its status item.
  static func make(coordinator: AgentMenuCoordinator) -> NSMenu {
    let menu = NSMenu()

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
