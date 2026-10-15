import SwiftUI

/// The vault section of the settings: one row per watched Obsidian vault,
/// with add and remove.
struct VaultSettingsView: View {
  @ObservedObject var viewModel: VaultSettingsViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Obsidian vaults")
        .font(.headline)
        .padding(8)
      if viewModel.rows.isEmpty {
        Text("No vault is sent to Ratatoskr Notes yet.")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 60)
      } else {
        List(viewModel.rows) { row in
          HStack {
            Text(row.displayName)
            Spacer()
            Button("Remove") {
              viewModel.remove(id: row.id)
            }
          }
        }
        .frame(minHeight: 80)
      }
      HStack {
        if let failure = viewModel.changeFailure {
          Text(failure)
            .font(.caption)
            .foregroundStyle(.red)
        }
        Spacer()
        if !viewModel.canReadVaultList {
          Button("Allow reading the Obsidian vault list…") {
            viewModel.allowReadingVaultList()
          }
          .help("Pick obsidian.json once, so each vault uses the vault key of Obsidian, as the plugin does.")
        }
        Button("Add Vault…") {
          viewModel.addVaultFromPicker()
        }
      }
      .padding(8)
    }
  }
}
