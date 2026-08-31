import SwiftUI

struct SettingsRootView: View {
  @ObservedObject var pairing: PairingOnboardingViewModel
  @ObservedObject var folders: FolderSettingsViewModel

  var body: some View {
    VStack(spacing: 0) {
      PairingOnboardingView(viewModel: pairing)
      Divider()
      FolderSettingsView(viewModel: folders)
    }
  }
}
