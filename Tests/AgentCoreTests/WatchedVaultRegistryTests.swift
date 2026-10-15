import AgentCore
import XCTest

final class WatchedVaultRegistryTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Work"), withIntermediateDirectories: true)
  }

  override func tearDown() {
    if let root {
      try? FileManager.default.removeItem(at: root)
    }
  }

  private var file: URL { root.appendingPathComponent("vault-preferences.json") }

  private func registry(key: String?) throws -> WatchedVaultRegistry {
    try WatchedVaultRegistry(
      store: FileWatchedVaultStore(fileURL: file),
      bookmarkStore: VaultBookmarkStub(url: root.appendingPathComponent("Work")),
      vaultKey: { _ in key },
      newKey: { "generated-key" }
    )
  }

  func testAddedVaultHasTheObsidianKeyAndTheFolderNameAndIsSaved() throws {
    let added = try registry(key: "a1b2c3d4e5f60718").addVault(at: root.appendingPathComponent("Work"))

    let reloaded = try registry(key: nil).vaults

    XCTAssertEqual(added.vaultKey, "a1b2c3d4e5f60718")
    XCTAssertEqual(added.displayName, "Work")
    XCTAssertEqual(added.bookmarkData, Data("bookmark".utf8))
    XCTAssertEqual(reloaded, [added])
  }

  func testVaultWithoutAnObsidianKeyGetsAGeneratedKeyOnce() throws {
    let registry = try registry(key: nil)

    let first = try registry.addVault(at: root.appendingPathComponent("Work"))
    let second = try registry.addVault(at: root.appendingPathComponent("Work"))

    XCTAssertEqual(first.vaultKey, "generated-key")
    XCTAssertEqual(second, first, "the same folder is one vault")
    XCTAssertEqual(registry.vaults.count, 1)
  }

  func testRemovedVaultIsGoneAfterAReload() throws {
    let registry = try registry(key: "a1b2c3d4e5f60718")
    let added = try registry.addVault(at: root.appendingPathComponent("Work"))
    let before = try self.registry(key: nil).vaults.count

    registry.removeVault(id: added.id)

    XCTAssertEqual(before, 1)
    XCTAssertEqual(try self.registry(key: nil).vaults, [])
  }
}

final class VaultBookmarkStub: FolderBookmarkStoring, @unchecked Sendable {
  private let url: URL

  init(url: URL) {
    self.url = url
  }

  func makeBookmarkData(for directoryURL: URL) throws -> Data { Data("bookmark".utf8) }
  func resolvedFolder(from bookmarkData: Data) throws -> ResolvedFolderLocation { ResolvedFolderLocation(url: url, isStale: false) }
  func startAccessing(_ resolved: ResolvedFolderLocation) -> Bool { true }
  func stopAccessing(_ resolved: ResolvedFolderLocation) {}
  func hasActiveAccess(to url: URL) -> Bool { false }
}
