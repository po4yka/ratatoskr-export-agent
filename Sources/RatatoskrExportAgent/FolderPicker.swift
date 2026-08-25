import AppKit

/// Presents a directory-choice dialog for adding a watched folder.
@MainActor
protocol FolderPicking {
  /// Runs the picker modally; returns the chosen directory, if any.
  func pickFolder() -> URL?
}

/// The production folder picker backed by NSOpenPanel.
@MainActor
struct OpenPanelFolderPicker: FolderPicking {
  func pickFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.message = "Choose a folder to watch for provider export archives."
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }
}
