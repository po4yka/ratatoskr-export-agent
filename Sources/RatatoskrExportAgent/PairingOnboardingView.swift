import AgentCore
import ServiceManagement
import SwiftUI

@MainActor
protocol MainAppLoginItemServing {
  var isEnabled: Bool { get }
  func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemMainAppLoginItem: MainAppLoginItemServing {
  var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
  func setEnabled(_ enabled: Bool) throws {
    if enabled { try SMAppService.mainApp.register() }
    else { try SMAppService.mainApp.unregister() }
  }
}

@MainActor
final class PairingOnboardingViewModel: ObservableObject {
  @Published var origin = ""
  @Published var pairingCode = ""
  @Published private(set) var status = DevicePairingStatusPresentation(
    title: "Not paired", detail: "Pair this agent before authenticated work can begin."
  )
  @Published private(set) var failure: String?
  @Published private(set) var isBusy = false
  @Published var launchAtLogin: Bool
  private let session: DeviceSessionCoordinator
  private let presenter = DevicePairingStatusViewModel()
  private let loginItem: any MainAppLoginItemServing

  init(
    session: DeviceSessionCoordinator,
    loginItem: any MainAppLoginItemServing = SystemMainAppLoginItem()
  ) {
    self.session = session
    self.loginItem = loginItem
    launchAtLogin = loginItem.isEnabled
    Task { await refreshStatus() }
  }

  func pair() {
    guard !isBusy else { return }
    isBusy = true
    failure = nil
    let submittedCode = pairingCode
    pairingCode = ""
    Task {
      defer { isBusy = false }
      guard let url = URL(string: origin), url.scheme?.lowercased() == "https" else {
        failure = "Enter an HTTPS Platform origin."
        return
      }
      do {
        try await session.pair(origin: url, code: submittedCode, displayName: Host.current().localizedName)
        await refreshStatus()
      } catch {
        failure = "Pairing was not accepted."
      }
    }
  }

  func unpair() {
    Task {
      try? await session.unpair()
      await refreshStatus()
    }
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      try loginItem.setEnabled(enabled)
      launchAtLogin = loginItem.isEnabled
      failure = nil
    } catch {
      launchAtLogin = loginItem.isEnabled
      failure = "Launch at login could not be changed."
    }
  }

  private func refreshStatus() async {
    let current = await session.status
    presenter.show(current)
    status = presenter.presentation
    if let identity = await session.pairedIdentity(), origin.isEmpty {
      origin = identity.origin.absoluteString
    }
  }
}

struct PairingOnboardingView: View {
  @ObservedObject var viewModel: PairingOnboardingViewModel

  var body: some View {
    Form {
      Section("Platform device") {
        Text(viewModel.status.title).font(.headline)
        Text(viewModel.status.detail).font(.caption).foregroundStyle(.secondary)
        TextField("https://platform.example", text: $viewModel.origin)
          .textFieldStyle(.roundedBorder)
        SecureField("One-time pairing code", text: $viewModel.pairingCode)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("Pair") { viewModel.pair() }
            .disabled(viewModel.isBusy || viewModel.pairingCode.isEmpty)
          Button("Unpair", role: .destructive) { viewModel.unpair() }
        }
      }
      Section("Background") {
        Toggle("Launch at login", isOn: Binding(
          get: { viewModel.launchAtLogin },
          set: { viewModel.setLaunchAtLogin($0) }
        ))
      }
      if let failure = viewModel.failure {
        Text(failure).foregroundStyle(.red).font(.caption)
      }
    }
    .formStyle(.grouped)
  }
}
