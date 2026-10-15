import AgentCore
import SwiftUI

/// One watched vault in the settings surface.
struct VaultRow: Identifiable, Equatable {
  var id: UUID
  var displayName: String
}

/// Drives the vault section of the settings from the vault registry.
@MainActor
final class VaultSettingsViewModel: ObservableObject {
  @Published private(set) var changeFailure: String?
  @Published private(set) var rows: [VaultRow] = []

  private let registry: WatchedVaultRegistry
  private let picker: any FolderPicking
  private let onChange: () -> Void

  init(
    registry: WatchedVaultRegistry,
    picker: any FolderPicking,
    grant: ObsidianConfigGrant? = nil,
    configPicker: (any FolderPicking)? = nil,
    onChange: @escaping () -> Void = {}
  ) {
    self.registry = registry
    self.picker = picker
    self.onChange = onChange
    refresh()
  }

  /// Whether the agent can read the vault list of Obsidian.
  var canReadVaultList: Bool {
    false
  }

  /// Asks the owner once to pick `obsidian.json`, and keeps a bookmark of it.
  func allowReadingVaultList() {}

  /// Runs the folder picker and registers the chosen vault.
  func addVaultFromPicker() {
    guard let url = picker.pickFolder() else { return }
    do {
      try registry.addVault(at: url)
      changeFailure = nil
      onChange()
    } catch {
      changeFailure = "The vault could not be added."
    }
    refresh()
  }

  /// Removes a vault. Its notes connection stays until the owner removes it.
  func remove(id: UUID) {
    registry.removeVault(id: id)
    onChange()
    refresh()
  }

  private func refresh() {
    rows = registry.vaults.map { VaultRow(id: $0.id, displayName: $0.displayName) }
  }
}
