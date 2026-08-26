import AgentCore
import XCTest

@testable import RatatoskrExportAgent

@MainActor
final class DevicePairingStatusTests: XCTestCase {
  func testPairedStatusShowsOnlyOriginDeviceAndExpiry() {
    let viewModel = DevicePairingStatusViewModel()
    let identity = fixtureIdentity()

    viewModel.show(.paired(identity))

    XCTAssertEqual(viewModel.presentation.title, "Paired")
    XCTAssertTrue(viewModel.presentation.detail.contains("ratatoskr.example"))
    XCTAssertTrue(viewModel.presentation.detail.contains(identity.deviceID.uuidString.prefix(8)))
    XCTAssertFalse(viewModel.presentation.detail.contains("fixture-device-secret"))
  }

  func testRevokedStatusDirectsUserToPairAgainWithoutSecrets() {
    let viewModel = DevicePairingStatusViewModel()

    viewModel.show(.rePairingRequired(fixtureIdentity()))

    XCTAssertEqual(viewModel.presentation.title, "Pairing required")
    XCTAssertTrue(viewModel.presentation.detail.contains("Pair again"))
    XCTAssertFalse(viewModel.presentation.detail.contains("fixture-refresh-token"))
  }

  private func fixtureIdentity() -> PairedDeviceIdentity {
    PairedDeviceIdentity(
      origin: URL(string: "https://ratatoskr.example")!,
      deviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000030")!,
      userID: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
      credentialExpiresAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
  }
}
