import AgentCore
import XCTest

final class VaultChannelStateRecoveryTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
  }

  override func tearDown() {
    if let root {
      try? FileManager.default.removeItem(at: root)
    }
  }

  func testCorruptFileIsMovedAsideAndTheStoreStartsEmpty() async throws {
    let file = root.appendingPathComponent("vault-channels.json")
    try Data("{\"vaults\":[".utf8).write(to: file)
    let lines = LogLines()
    let store = FileVaultChannelStateStore(
      fileURL: file, now: { Date(timeIntervalSince1970: 1_800_000_000) }, log: { lines.append($0) }
    )

    let loaded = try? await store.load(vaultKey: "vault-key-1")
    let state = VaultChannelState(vaultKey: "vault-key-1", connectionID: "00000000-0000-7000-8000-000000000001", committedSequence: 2)
    try? await store.save(state)
    let saved = try? await store.load(vaultKey: "vault-key-1")

    let aside = root.appendingPathComponent("vault-channels.json.corrupt-1800000000")
    XCTAssertNil(loaded)
    XCTAssertEqual(try? String(contentsOf: aside, encoding: .utf8), "{\"vaults\":[", "the corrupt bytes are kept aside")
    XCTAssertEqual(saved, state, "the store works again")
    XCTAssertEqual(lines.values.count, 1)
    XCTAssertTrue(lines.values.first?.contains("vault-channels.json.corrupt-1800000000") ?? false)
  }
}

private final class LogLines: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [String] = []

  var values: [String] { lock.withLock { stored } }

  func append(_ line: String) {
    lock.withLock { stored.append(line) }
  }
}
