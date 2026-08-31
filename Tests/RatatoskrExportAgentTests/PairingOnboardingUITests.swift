import AgentCore
import XCTest

@testable import RatatoskrExportAgent

@MainActor
final class PairingOnboardingUITests: XCTestCase {
  func testLaunchAtLoginUsesMainAppRegistrationAndReflectsFailure() {
    let loginItem = LoginItemFixture()
    let viewModel = PairingOnboardingViewModel(
      session: DeviceSessionCoordinator(
        transport: UnavailablePairingTransport(),
        credentialStore: InMemoryDeviceCredentialStore()
      ),
      loginItem: loginItem
    )

    viewModel.setLaunchAtLogin(true)
    XCTAssertTrue(viewModel.launchAtLogin)
    XCTAssertEqual(loginItem.changes, [true])

    loginItem.shouldFail = true
    viewModel.setLaunchAtLogin(false)
    XCTAssertTrue(viewModel.launchAtLogin)
    XCTAssertNotNil(viewModel.failure)
  }
}

@MainActor
private final class LoginItemFixture: MainAppLoginItemServing {
  var isEnabled = false
  var shouldFail = false
  var changes: [Bool] = []

  func setEnabled(_ enabled: Bool) throws {
    changes.append(enabled)
    if shouldFail { throw FixtureError.refused }
    isEnabled = enabled
  }
}

private enum FixtureError: Error { case refused }

private struct UnavailablePairingTransport: PlatformDeviceTransport {
  func pair(_: DevicePairingRequest) async throws -> DevicePairingResponse {
    throw PlatformDeviceTransportError.unavailable
  }
}
