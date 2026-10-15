import AgentCore
import XCTest

final class VaultRuntimeComponentTests: XCTestCase {
  private func vault(_ name: String) -> RuntimeVault {
    RuntimeVault(
      vault: WatchedVault(id: UUID(), displayName: name, vaultKey: "key-\(name)", bookmarkData: Data()),
      folder: URL(fileURLWithPath: "/fixture/\(name)")
    )
  }

  func testEachVaultRunsItsSyncAndARemovedVaultStops() async {
    let work = vault("Work")
    let notes = vault("Notes")
    let added = vault("Added")
    let list = VaultList([work, notes])
    let log = SyncLog()
    let component = VaultRuntimeComponent(vaults: { list.value }, makeSync: { FakeSync(name: $0.vault.displayName, log: log) })

    await component.start()
    list.value = [work, added]
    await component.reconcile()
    await component.stop()

    XCTAssertEqual(
      log.events,
      ["launch Work", "launch Notes", "stop Notes", "launch Added", "stop Work", "stop Added"]
    )
  }

  @MainActor
  func testRegistryGivesEachVaultWithItsResolvedFolder() throws {
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vault-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let registry = try WatchedVaultRegistry(
      store: FileWatchedVaultStore(fileURL: folder.appendingPathComponent(".prefs.json")),
      bookmarkStore: VaultBookmarkStub(url: folder), vaultKey: { _ in "key" }, newKey: { "generated" }
    )
    let added = try registry.addVault(at: folder)

    XCTAssertEqual(registry.runtimeVaults(), [RuntimeVault(vault: added, folder: folder)])
  }
}

private final class VaultList: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [RuntimeVault]

  init(_ value: [RuntimeVault]) {
    stored = value
  }

  var value: [RuntimeVault] {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

private final class SyncLog: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [String] = []

  var events: [String] { lock.withLock { stored } }

  func append(_ event: String) {
    lock.withLock { stored.append(event) }
  }
}

private struct FakeSync: VaultSyncing {
  let name: String
  let log: SyncLog

  func launch() { log.append("launch \(name)") }
  func stop() { log.append("stop \(name)") }
  func status() async -> VaultSyncStatus { .connected }
  func connectAgain() async {}
}
