import XCTest

@testable import RatatoskrExportAgent

@MainActor
final class StatusItemMenuTests: XCTestCase {
  func testStatusItemMenuOffersSettingsAndQuit() {
    let menu = AgentMenu.make(coordinator: AgentMenuCoordinator())

    let titles = menu.items.map(\.title)
    XCTAssertTrue(
      titles.contains(AgentMenu.settingsTitle),
      "the status-bar menu must offer a Settings item, got: \(titles)")
    XCTAssertTrue(
      titles.contains(AgentMenu.quitTitle),
      "the status-bar menu must offer a Quit item, got: \(titles)")

    let settingsItem = menu.items.first { $0.title == AgentMenu.settingsTitle }
    XCTAssertNotNil(
      settingsItem?.action,
      "the Settings item must have an action wired")
    XCTAssertEqual(
      settingsItem?.action, #selector(AgentMenuCoordinator.settingsSelected),
      "the Settings item must route to the coordinator")
    XCTAssertEqual(
      menu.items.first { $0.title == AgentMenu.quitTitle }?.action,
      #selector(AgentMenuCoordinator.quitSelected),
      "the Quit item must route to termination")
  }
}
