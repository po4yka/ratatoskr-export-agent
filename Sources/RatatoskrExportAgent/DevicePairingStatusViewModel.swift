import AgentCore
import SwiftUI

struct DevicePairingStatusPresentation: Equatable {
  var title: String
  var detail: String
}

@MainActor
final class DevicePairingStatusViewModel: ObservableObject {
  @Published private(set) var presentation = DevicePairingStatusPresentation(
    title: "Unavailable", detail: ""
  )

  func show(_ status: DevicePairingStatus) {
    switch status {
    case .unpaired:
      presentation = DevicePairingStatusPresentation(
        title: "Not paired", detail: "Pair this agent before authenticated work can begin."
      )
    case let .paired(identity):
      presentation = DevicePairingStatusPresentation(
        title: "Paired", detail: pairedDetail(for: identity)
      )
    case .rePairingRequired:
      presentation = DevicePairingStatusPresentation(
        title: "Pairing required", detail: "Pair again from an approved primary session."
      )
    }
  }

  private func pairedDetail(for identity: PairedDeviceIdentity) -> String {
    let host = identity.origin.host ?? "configured Platform"
    let prefix = identity.deviceID.uuidString.prefix(8)
    return "\(host) · device \(prefix) · expires \(identity.credentialExpiresAt.formatted())"
  }
}
