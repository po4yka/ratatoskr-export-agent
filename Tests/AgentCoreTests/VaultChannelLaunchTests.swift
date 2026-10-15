import AgentCore
import XCTest

final class VaultChannelLaunchTests: XCTestCase {
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

  func testLaunchAfterStopStartsNothing() async throws {
    let server = FakeNotesServer()
    let source = RunningEventSource()
    let sync = makeSync(server, source)

    sync.stop()
    sync.launch()
    try await Task.sleep(nanoseconds: 200_000_000)

    XCTAssertEqual(source.starts, 0, "a stopped sync does not watch the vault")
    XCTAssertEqual(server.log.count, 0, "a stopped sync does not connect")
  }

  func testStopBeforeTheLaunchTaskRunsLeavesNothingRunning() async throws {
    let server = FakeNotesServer()
    let source = RunningEventSource()
    let sync = makeSync(server, source)

    sync.launch()
    sync.stop()
    try await Task.sleep(nanoseconds: 200_000_000)

    XCTAssertFalse(source.running, "the watcher does not run after stop")
  }

  private func makeSync(_ server: FakeNotesServer, _ source: RunningEventSource) -> VaultChannelSync {
    VaultChannelSync(
      coordinator: { onChanges in
        VaultModeCoordinator(
          source: source, scanner: VaultScanner(root: self.vault), watcher: VaultWatcher(firstSequence: 1),
          now: { Date(timeIntervalSinceReferenceDate: 100) }, onChanges: onChanges
        )
      },
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture",
      retry: VaultChannelRetry(sleep: { _ in })
    )
  }
}

private final class RunningEventSource: VaultEventSource, @unchecked Sendable {
  private let lock = NSLock()
  private var storedStarts = 0
  private var storedRunning = false

  var starts: Int { lock.withLock { storedStarts } }
  var running: Bool { lock.withLock { storedRunning } }

  func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {
    lock.withLock {
      storedStarts += 1
      storedRunning = true
    }
  }

  func stop() {
    lock.withLock { storedRunning = false }
  }
}
