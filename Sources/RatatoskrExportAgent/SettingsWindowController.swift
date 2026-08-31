import AgentCore
import AppKit
import SwiftUI

/// Presents the settings window hosting the folder-settings surface.
@MainActor
final class SettingsWindowController: NSWindowController {
  private let viewModel: FolderSettingsViewModel
  private let pairingViewModel: PairingOnboardingViewModel

  init(
    registry: WatchedFolderRegistry,
    session: DeviceSessionCoordinator,
    onFoldersChanged: @escaping () -> Void = {}
  ) {
    viewModel = FolderSettingsViewModel(registry: registry, onChange: onFoldersChanged)
    pairingViewModel = PairingOnboardingViewModel(session: session)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Ratatoskr Settings"
    window.contentView = NSHostingView(
      rootView: SettingsRootView(
        pairing: pairingViewModel, folders: viewModel
      ))
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SettingsWindowController is not created from coders")
  }

  func showSettings() {
    NSApplication.shared.activate()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }
}
