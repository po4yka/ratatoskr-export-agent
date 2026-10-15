import AgentCore
import XCTest

final class VaultSyncStatusTests: XCTestCase {
  private var vault: URL!
  private let first = "00000000-0000-7000-8000-000000000001"

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

  func testStatusIsConnectedAfterTheManifestAndRetryingDuringTheBackoff() async throws {
    let server = FakeNotesServer()
    let gate = BackoffGate()
    let (sync, sink) = makeSync(server, sleep: { _ in await gate.hold() })
    try await sync.start(drainInterval: nil)
    let connected = await sync.status()
    server.script("/changes", status: 503, body: #"{"code":"notes.service.unavailable","message":"m","retryable":true}"#)

    sink.onChanges?([VaultChange(sequence: 1, kind: .deleted, path: "1.md")])
    await gate.waitUntilHeld()
    let retrying = await sync.status()
    await gate.release()
    for _ in 0..<200 where server.committed == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let after = await sync.status()
    sync.stop()

    XCTAssertEqual(connected, .connected)
    XCTAssertEqual(retrying, .retrying)
    XCTAssertEqual(after, .connected)
  }

  func testRemovedVaultConnectsAgainWithANewConnectionAndForgetsTheSavedOne() async throws {
    let server = FakeNotesServer()
    let store = FileVaultChannelStateStore(fileURL: vault.appendingPathComponent(".state/vault-channels.json"))
    try await store.save(
      VaultChannelState(vaultKey: "vault-key-1", connectionID: "00000000-0000-7000-8000-000000000009", committedSequence: 3)
    )
    server.script("/manifest", status: 410, body: #"{"code":"notes.connection.removed","message":"m","retryable":false}"#)
    let (sync, _) = makeSync(server, store: store, sleep: { _ in })

    _ = await capturedError { try await sync.start(drainInterval: nil); return "" }
    let removed = await sync.status()
    await sync.connectAgain()
    for _ in 0..<200 where await sync.status() != .connected {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let after = await sync.status()
    let saved = try await store.load(vaultKey: "vault-key-1")
    sync.stop()

    XCTAssertEqual(removed, .stopped(code: "notes.connection.removed"))
    XCTAssertEqual(after, .connected)
    XCTAssertEqual(saved?.connectionID, first, "the saved connection is the new one")
    XCTAssertTrue(server.routes.contains("POST v1/notes/connections"))
  }

  private func makeSync(
    _ server: FakeNotesServer,
    store: (any VaultChannelStateStoring)? = nil,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void
  ) -> (VaultChannelSync, StatusSinkBox) {
    let sink = StatusSinkBox()
    let sync = VaultChannelSync(
      coordinator: { onChanges in
        sink.onChanges = onChanges
        return VaultModeCoordinator(
          source: QuietEventSource(), scanner: VaultScanner(root: self.vault), watcher: VaultWatcher(firstSequence: 1),
          now: { Date(timeIntervalSinceReferenceDate: 100) }, onChanges: onChanges
        )
      },
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture", stateStore: store,
      retry: VaultChannelRetry(sleep: sleep)
    )
    return (sync, sink)
  }
}

/// Holds a backoff until the test releases it.
private actor BackoffGate {
  private var held = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var heldWaiter: CheckedContinuation<Void, Never>?

  func hold() async {
    held = true
    heldWaiter?.resume()
    heldWaiter = nil
    await withCheckedContinuation { waiter = $0 }
  }

  func waitUntilHeld() async {
    if !held {
      await withCheckedContinuation { heldWaiter = $0 }
    }
  }

  func release() {
    waiter?.resume()
    waiter = nil
  }
}

private final class StatusSinkBox: @unchecked Sendable {
  var onChanges: (@Sendable ([VaultChange]) -> Void)?
}

private final class QuietEventSource: VaultEventSource, @unchecked Sendable {
  func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {}
  func stop() {}
}
