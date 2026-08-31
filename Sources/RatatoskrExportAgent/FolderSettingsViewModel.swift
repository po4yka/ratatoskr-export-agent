import AgentCore
import SwiftUI

/// One displayable watched-folder row in the settings surface.
struct FolderRow: Identifiable, Equatable {
  var id: UUID
  var displayPath: String
  var isEnabled: Bool
  var archivePolicy: FolderArchivePolicy
  var accessState: FolderAccessState
}

/// Drives the folder-settings view from the watched-folder registry.
@MainActor
final class FolderSettingsViewModel: ObservableObject {
  /// Generic description of the last failed settings change, if any.
  /// Carries no filesystem detail on purpose.
  @Published private(set) var changeFailure: String?

  @Published private(set) var rows: [FolderRow] = []

  private let registry: WatchedFolderRegistry
  private let picker: any FolderPicking
  private let onChange: () -> Void

  init(
    registry: WatchedFolderRegistry,
    picker: any FolderPicking = OpenPanelFolderPicker(),
    onChange: @escaping () -> Void = {}
  ) {
    self.registry = registry
    self.picker = picker
    self.onChange = onChange
    refresh()
  }

  /// Runs the folder picker and registers the chosen directory.
  func addFolderFromPicker() {
    guard let url = picker.pickFolder() else { return }
    do {
      _ = try registry.addFolder(at: url)
      changeFailure = nil
      onChange()
    } catch {
      changeFailure = "The folder could not be added."
    }
    refresh()
  }

  /// Rebuilds rows from the registry's current entries and access states.
  func refresh() {
    rows = registry.folders.map { entry in
      FolderRow(
        id: entry.id,
        displayPath: entry.displayPath,
        isEnabled: entry.isEnabled,
        archivePolicy: entry.archivePolicy,
        accessState: registry.accessState(for: entry.id)
      )
    }
  }

  func setEnabled(_ enabled: Bool, id: UUID) {
    do {
      try registry.setEnabled(enabled, for: id)
      changeFailure = nil
      onChange()
    } catch {
      changeFailure = "The change could not be saved."
    }
    refresh()
  }

  func setArchivePolicy(_ policy: FolderArchivePolicy, id: UUID) {
    do {
      try registry.setArchivePolicy(policy, for: id)
      changeFailure = nil
      onChange()
    } catch {
      changeFailure = "The change could not be saved."
    }
    refresh()
  }

  /// Removes an already-confirmed folder entry through the registry.
  func removeConfirmed(id: UUID) {
    registry.removeFolder(id: id)
    onChange()
    refresh()
  }
}
