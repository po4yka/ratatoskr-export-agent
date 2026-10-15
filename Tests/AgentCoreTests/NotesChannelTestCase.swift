import AgentCore
import XCTest

/// A temporary vault with a 1.5 MiB file and an empty file, and a client of
/// it that talks to a `FakeNotesServer`.
class NotesChannelTestCase: XCTestCase {
  var vault: URL!
  let empty = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

  override func setUpWithError() throws {
    vault = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    try Data(repeating: 7, count: 1_572_864).write(to: vault.appendingPathComponent("A.pdf"))
    try Data().write(to: vault.appendingPathComponent("Empty.md"))
  }

  override func tearDown() {
    if let vault {
      try? FileManager.default.removeItem(at: vault)
    }
  }

  func client(_ server: FakeNotesServer, store: (any VaultChannelStateStoring)? = nil) -> NotesChannelClient {
    var scanner = VaultScanner(root: vault)
    _ = scanner.rescan()
    let manifest = VaultManifest(index: scanner.index)
    return NotesChannelClient(
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture", stateStore: store,
      manifest: { manifest }
    )
  }
}
