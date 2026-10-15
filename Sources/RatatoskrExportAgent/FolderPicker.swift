import AgentCore
import AppKit
import UniformTypeIdentifiers

/// Presents a directory-choice dialog for adding a watched folder.
@MainActor
protocol FolderPicking {
  /// Runs the picker modally; returns the chosen directory, if any.
  func pickFolder() -> URL?
}

/// The production folder picker backed by NSOpenPanel.
@MainActor
struct OpenPanelFolderPicker: FolderPicking {
  var message = "Choose a folder to watch for provider export archives."

  func pickFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.message = message
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }
}

/// Asks the owner once for the vault list of Obsidian, `obsidian.json`, in
/// its usual folder. The pick gives the sandboxed agent a read grant that a
/// security-scoped bookmark keeps.
@MainActor
struct OpenPanelObsidianConfigPicker: FolderPicking {
  func pickFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.json]
    panel.directoryURL = ObsidianVaultKey.userConfig.deletingLastPathComponent()
    panel.message = "Choose obsidian.json, the vault list of Obsidian, so the vault key matches the plugin."
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }
}
