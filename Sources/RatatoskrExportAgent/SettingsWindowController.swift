import AgentCore
import AppKit
import SwiftUI

/// Presents the settings window hosting the folder-settings surface.
@MainActor
final class SettingsWindowController: NSWindowController {
  private let viewModel: FolderSettingsViewModel

  init(registry: WatchedFolderRegistry) {
    viewModel = FolderSettingsViewModel(registry: registry)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Ratatoskr Settings"
    window.contentView = NSHostingView(rootView: FolderSettingsView(viewModel: viewModel))
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("SettingsWindowController is not created from coders")
  }

  /// Builds the controller over the default preferences location.
  /// Returns nil when the stored document cannot be loaded; callers must
  /// surface that failure instead of retrying silently.
  static func makeDefault() -> SettingsWindowController? {
    guard
      let registry = try? WatchedFolderRegistry(
        preferencesStore: FileFolderPreferencesStore(fileURL: preferencesFileURL()),
        bookmarkStore: SecurityScopedBookmarkStore()
      )
    else {
      return nil
    }
    return SettingsWindowController(registry: registry)
  }

  func showSettings() {
    NSApplication.shared.activate()
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
  }

  private static func preferencesFileURL() -> URL {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.temporaryDirectory
    let directory = support.appendingPathComponent("Ratatoskr", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("folder-preferences.json")
  }
}
