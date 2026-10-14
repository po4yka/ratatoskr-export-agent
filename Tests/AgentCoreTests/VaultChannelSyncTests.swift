import AgentCore
import XCTest

final class VaultChannelSyncTests: XCTestCase {
  private var vault: URL!

  override func setUpWithError() throws {
    vault = try FileManager.default.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
      create: true
    )
    try Data("alpha".utf8).write(to: vault.appendingPathComponent("A.md"))
  }

  override func tearDown() {
    if let vault {
      try? FileManager.default.removeItem(at: vault)
    }
  }

  func testWatchedVaultSendsItsManifestAfterTheConnectAndItsBatchesAfter() async throws {
    let server = FakeNotesServer()
    let source = SyncEventSource()
    let start = Date(timeIntervalSinceReferenceDate: 100)
    let sync = VaultChannelSync(
      coordinator: { onChanges in
        VaultModeCoordinator(
          source: source, scanner: VaultScanner(root: self.vault), watcher: VaultWatcher(firstSequence: 1),
          now: { start }, onChanges: onChanges
        )
      },
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture"
    )

    try await sync.start(drainInterval: nil)
    try Data().write(to: vault.appendingPathComponent("B.md"))
    source.emit([vault.appendingPathComponent("B.md").path])
    sync.coordinator.drain(at: start.addingTimeInterval(10))
    for _ in 0..<200 where server.batches.isEmpty {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    sync.stop()

    XCTAssertEqual(
      server.routes.filter { !$0.contains("/blobs") },
      [
        "POST v1/notes/connections",
        "POST v1/notes/connections/{id}/manifest",
        "POST v1/notes/connections/{id}/manifest",
        "POST v1/notes/connections/{id}/changes",
      ]
    )
    let manifest = try? JSONDecoder().decode(VaultManifest.self, from: server.log.dropFirst().first?.body ?? Data())
    XCTAssertEqual(manifest?.entries.map(\.path), ["A.md"])
    XCTAssertEqual(server.batches, [[1]])
    XCTAssertTrue(source.stopped)
  }
}

private final class SyncEventSource: VaultEventSource, @unchecked Sendable {
  private var handler: (@Sendable ([String], Bool) -> Void)?
  private(set) var stopped = false

  func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {
    handler = onEvents
  }

  func stop() {
    stopped = true
  }

  func emit(_ paths: [String]) {
    handler?(paths, false)
  }
}
