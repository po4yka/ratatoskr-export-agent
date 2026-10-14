import AgentCore
import XCTest

final class VaultManifestTests: XCTestCase {
  private var vault: URL!

  override func setUpWithError() throws {
    vault = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let vault {
      try? FileManager.default.removeItem(at: vault)
    }
  }

  func testManifestOfTheScanHasTheNotesKeysInPathOrder() throws {
    try FileManager.default.createDirectory(at: vault.appendingPathComponent("Notes"), withIntermediateDirectories: true)
    try Data().write(to: vault.appendingPathComponent("Notes/Empty.md"))
    try Data("alpha".utf8).write(to: vault.appendingPathComponent("A.md"))
    var scanner = VaultScanner(root: vault)
    _ = scanner.rescan()

    let json = String(bytes: try VaultManifest(index: scanner.index).encoded(), encoding: .utf8)

    XCTAssertEqual(
      json,
      #"{"entries":[{"length_bytes":5,"path":"A.md","#
        + #""sha256":"8ed3f6ad685b959ead7022518e1af76cd816f8e8ec7ccdda1ed4018e8f2223f8"},"#
        + #"{"length_bytes":0,"path":"Notes/Empty.md","#
        + #""sha256":"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"}]}"#
    )
  }
}
