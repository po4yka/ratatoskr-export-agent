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
  /// Whether the owner granted the vault list of Obsidian (`obsidian.json`).
  @Published private(set) var canReadVaultList = false

  private let registry: WatchedVaultRegistry
  private let picker: any FolderPicking
  private let grant: ObsidianConfigGrant?
  private let configPicker: (any FolderPicking)?
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
    self.grant = grant
    self.configPicker = configPicker
    self.onChange = onChange
    refresh()
  }

  /// Asks the owner once to pick `obsidian.json`, and keeps a bookmark of it.
  /// The refresh that follows gives each vault the key of Obsidian.
  func allowReadingVaultList() {
    guard let grant, let url = configPicker?.pickFolder() else { return }
    do {
      try grant.grant(config: url)
      changeFailure = nil
      onChange()
    } catch {
      changeFailure = "The file is not the vault list of Obsidian (obsidian.json)."
    }
    refresh()
  }

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
    canReadVaultList = grant?.isGranted ?? false
  }
}
