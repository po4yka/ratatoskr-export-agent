import AgentCore
import XCTest

/// Reads only a fixture `obsidian.json` in a temporary directory, never the
/// Obsidian profile of the user.
final class ObsidianVaultKeyTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    for name in ["Work", "Notes"] {
      try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    let config = """
      {"vaults":{"a1b2c3d4e5f60718":{"path":"\(root.appendingPathComponent("Work").path)","ts":1,"open":true},\
      "0f1e2d3c4b5a6978":{"path":"\(root.appendingPathComponent("Notes").path)","ts":2}},"frame":"hidden"}
      """
    try Data(config.utf8).write(to: root.appendingPathComponent("obsidian.json"))
  }

  override func tearDown() {
    if let root {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testKeyIsTheVaultIdOfObsidianForTheVaultPath() {
    let config = root.appendingPathComponent("obsidian.json")

    XCTAssertEqual(ObsidianVaultKey.key(forVault: root.appendingPathComponent("Notes"), config: config), "0f1e2d3c4b5a6978")
    XCTAssertEqual(ObsidianVaultKey.key(forVault: root.appendingPathComponent("Work/"), config: config), "a1b2c3d4e5f60718")
  }

  func testLinkedPathFindsTheSameVault() throws {
    let link = root.appendingPathComponent("Link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("Work"))

    XCTAssertEqual(ObsidianVaultKey.key(forVault: link, config: root.appendingPathComponent("obsidian.json")), "a1b2c3d4e5f60718")
  }

  func testUnknownVaultMissingOrInvalidConfigGiveNoKey() throws {
    let config = root.appendingPathComponent("obsidian.json")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Other"), withIntermediateDirectories: true)

    XCTAssertNil(ObsidianVaultKey.key(forVault: root.appendingPathComponent("Other"), config: config))
    XCTAssertNil(ObsidianVaultKey.key(forVault: root.appendingPathComponent("Work"), config: root.appendingPathComponent("none.json")))
    try Data("{".utf8).write(to: config)
    XCTAssertNil(ObsidianVaultKey.key(forVault: root.appendingPathComponent("Work"), config: config))
  }
}
