import AgentCore
import XCTest

/// Uses only a fixture `obsidian.json` in a temporary directory, never the
/// Obsidian profile of the user.
final class ObsidianConfigGrantTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
    let config = #"{"vaults":{"a1b2c3d4e5f60718":{"path":"\#(root.appendingPathComponent("Work").path)","ts":1}}}"#
    try Data(config.utf8).write(to: root.appendingPathComponent("obsidian.json"))
  }

  override func tearDown() {
    if let root {
      try? FileManager.default.removeItem(at: root)
    }
  }

  private var bookmarkFile: URL { root.appendingPathComponent("obsidian-config.bookmark") }

  func testGrantedConfigGivesTheVaultKeyWithBalancedAccess() throws {
    let access = CountingBookmarkStore(url: root.appendingPathComponent("obsidian.json"))
    let before = ObsidianConfigGrant(bookmarkFile: bookmarkFile, bookmarkStore: access)
    let keyBefore = before.key(forVault: root.appendingPathComponent("Work"))

    try before.grant(config: root.appendingPathComponent("obsidian.json"))
    let after = ObsidianConfigGrant(bookmarkFile: bookmarkFile, bookmarkStore: access)
    let key = after.key(forVault: root.appendingPathComponent("Work"))

    XCTAssertNil(keyBefore)
    XCTAssertTrue(after.isGranted, "the grant is saved")
    XCTAssertEqual(key, "a1b2c3d4e5f60718")
    XCTAssertEqual(access.starts, 1)
    XCTAssertEqual(access.stops, access.starts, "each access that began ends")
  }

  func testAFileThatIsNotTheVaultListIsRefused() throws {
    let other = root.appendingPathComponent("notes.json")
    try Data("{}".utf8).write(to: other)
    let grant = ObsidianConfigGrant(bookmarkFile: bookmarkFile, bookmarkStore: CountingBookmarkStore(url: other))

    XCTAssertThrowsError(try grant.grant(config: other))
    XCTAssertFalse(grant.isGranted)
  }

  @MainActor
  func testRegistryAdoptsTheObsidianKeyAndClearsTheStateOfTheGeneratedKey() async throws {
    let key = KeyBox()
    let registry = try WatchedVaultRegistry(
      store: FileWatchedVaultStore(fileURL: root.appendingPathComponent("vault-preferences.json")),
      bookmarkStore: VaultBookmarkStub(url: root.appendingPathComponent("Work")),
      vaultKey: { _ in key.value }, newKey: { "generated-key" }
    )
    try registry.addVault(at: root.appendingPathComponent("Work"))
    let states = FileVaultChannelStateStore(fileURL: root.appendingPathComponent("vault-channels.json"))
    try await states.save(VaultChannelState(vaultKey: "generated-key", connectionID: "c-1", committedSequence: 5))
    key.value = "a1b2c3d4e5f60718"

    let adopted = await registry.adoptObsidianKeys(clearing: states)
    let again = await registry.adoptObsidianKeys(clearing: states)

    XCTAssertEqual(adopted, ["generated-key"])
    XCTAssertEqual(again, [])
    XCTAssertEqual(registry.vaults.map(\.vaultKey), ["a1b2c3d4e5f60718"])
    let cleared = try await states.load(vaultKey: "generated-key")
    XCTAssertNil(cleared, "the vault connects again with the Obsidian key")
  }
}

final class KeyBox: @unchecked Sendable {
  var value: String?
}

final class CountingBookmarkStore: FolderBookmarkStoring, @unchecked Sendable {
  private let url: URL
  private let lock = NSLock()
  private var storedStarts = 0
  private var storedStops = 0

  init(url: URL) {
    self.url = url
  }

  var starts: Int { lock.withLock { storedStarts } }
  var stops: Int { lock.withLock { storedStops } }

  func makeBookmarkData(for directoryURL: URL) throws -> Data { Data("config-bookmark".utf8) }
  func resolvedFolder(from bookmarkData: Data) throws -> ResolvedFolderLocation { ResolvedFolderLocation(url: url, isStale: false) }
  func startAccessing(_ resolved: ResolvedFolderLocation) -> Bool {
    lock.withLock { storedStarts += 1 }
    return true
  }
  func stopAccessing(_ resolved: ResolvedFolderLocation) {
    lock.withLock { storedStops += 1 }
  }
  func hasActiveAccess(to url: URL) -> Bool { false }
}
