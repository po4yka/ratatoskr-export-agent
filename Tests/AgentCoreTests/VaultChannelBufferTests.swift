import AgentCore
import XCTest

final class VaultChannelBufferTests: XCTestCase {
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

  func testChangesOverTheBoundWhileASendWaitsBecomeOneManifest() async throws {
    let server = FakeNotesServer()
    let gated = GatedChanges(server: server)
    let sink = SinkBox()
    let sync = VaultChannelSync(
      coordinator: { onChanges in
        sink.onChanges = onChanges
        return VaultModeCoordinator(
          source: SilentEventSource(), scanner: VaultScanner(root: self.vault), watcher: VaultWatcher(firstSequence: 1),
          now: { Date(timeIntervalSinceReferenceDate: 100) }, onChanges: onChanges
        )
      },
      http: gated, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture",
      retry: VaultChannelRetry(sleep: { _ in }), maximumBufferedChanges: 3
    )
    try await sync.start(drainInterval: nil)
    let started = server.log.count

    sink.onChanges?([VaultChange(sequence: 1, kind: .deleted, path: "1.md")])
    await gated.waitUntilHeld()
    for index in 2...6 {
      sink.onChanges?([VaultChange(sequence: UInt64(index), kind: .deleted, path: "\(index).md")])
    }
    await gated.release()
    for _ in 0..<200 where server.routes.count < started + 2 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    try await Task.sleep(nanoseconds: 50_000_000)
    sync.stop()

    XCTAssertEqual(
      Array(server.routes.dropFirst(started)),
      ["POST v1/notes/connections/{id}/changes", "POST v1/notes/connections/{id}/manifest"],
      "the changes over the bound are not queued: one manifest describes the vault"
    )
    XCTAssertEqual(server.batches, [[1]])
  }
}

/// Holds the first change batch until the test releases it.
private actor GatedChanges: NotesChannelHTTP {
  private let server: FakeNotesServer
  private var held = false
  private var released = false
  private var waiter: CheckedContinuation<Void, Never>?
  private var holdWaiter: CheckedContinuation<Void, Never>?

  init(server: FakeNotesServer) {
    self.server = server
  }

  func perform(_ request: NotesChannelRequest) async throws -> NotesChannelAnswer {
    if request.path.hasSuffix("/changes"), !released, !held {
      held = true
      holdWaiter?.resume()
      holdWaiter = nil
      await withCheckedContinuation { waiter = $0 }
    }
    return try await server.perform(request)
  }

  func waitUntilHeld() async {
    if !held {
      await withCheckedContinuation { holdWaiter = $0 }
    }
  }

  func release() {
    released = true
    waiter?.resume()
    waiter = nil
  }
}

private final class SinkBox: @unchecked Sendable {
  var onChanges: (@Sendable ([VaultChange]) -> Void)?
}

private final class SilentEventSource: VaultEventSource, @unchecked Sendable {
  func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {}
  func stop() {}
}
