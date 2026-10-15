import SwiftUI

struct SettingsRootView: View {
  @ObservedObject var pairing: PairingOnboardingViewModel
  @ObservedObject var folders: FolderSettingsViewModel
  @ObservedObject var vaults: VaultSettingsViewModel

  var body: some View {
    VStack(spacing: 0) {
      PairingOnboardingView(viewModel: pairing)
      Divider()
      FolderSettingsView(viewModel: folders)
      Divider()
      VaultSettingsView(viewModel: vaults)
    }
  }
}
