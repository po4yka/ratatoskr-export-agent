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

  init(registry: WatchedVaultRegistry, picker: any FolderPicking, onChange: @escaping () -> Void = {}) {
    self.registry = registry
    self.picker = picker
    self.onChange = onChange
  }

  /// Runs the folder picker and registers the chosen vault.
  func addVaultFromPicker() {}

  /// Removes a vault.
  func remove(id: UUID) {}
}
