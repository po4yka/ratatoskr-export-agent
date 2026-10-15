import AgentCore
import XCTest

final class VaultChannelRetryTests: XCTestCase {
  private var vault: URL!
  private let unavailable = #"{"code":"notes.service.unavailable","message":"m","retryable":true}"#

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

  func testDelaysDoubleFrom5SecondsTo5MinutesAndJitterTakesUpToHalf() {
    let full = VaultChannelRetry(jitter: { 1 }, sleep: { _ in })
    let half = VaultChannelRetry(jitter: { 0 }, sleep: { _ in })

    XCTAssertEqual((1...8).map(full.delay(attempt:)), [5, 10, 20, 40, 80, 160, 300, 300])
    XCTAssertEqual((1...8).map(half.delay(attempt:)), [2.5, 5, 10, 20, 40, 80, 150, 150])
  }

  func testFailedSendIsSentAgainAfterTheBackoffWithoutAFileEvent() async throws {
    let server = FakeNotesServer()
    let sleeps = Sleeps()
    let (sync, source) = makeSync(server, sleeps)
    try await sync.start(drainInterval: nil)
    server.script("/changes", status: 503, body: unavailable)
    server.script("/changes", status: 503, body: unavailable)

    try Data().write(to: vault.appendingPathComponent("B.md"))
    source.emit([vault.appendingPathComponent("B.md").path])
    sync.coordinator.drain(at: Date(timeIntervalSinceReferenceDate: 200))
    for _ in 0..<200 where server.committed == 0 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    sync.stop()

    XCTAssertEqual(sleeps.delays, [5, 10])
    XCTAssertEqual(server.batches, [[1], [1], [1]])
    XCTAssertEqual(server.committed, 1)
  }

  func testFailedStartIsRetriedByTheTimer() async throws {
    let server = FakeNotesServer()
    let sleeps = Sleeps()
    let (sync, _) = makeSync(server, sleeps)
    server.script("/manifest", status: 503, body: unavailable)

    let failure = await capturedError { try await sync.start(drainInterval: nil); return "" }
    for _ in 0..<200 where server.routes.filter({ $0.hasSuffix("/manifest") }).count < 3 {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let status = await sync.client.status
    sync.stop()

    XCTAssertNotNil(failure)
    XCTAssertEqual(sleeps.delays, [5])
    XCTAssertEqual(server.routes.filter { $0.hasSuffix("/manifest") }.count, 3, "a refused manifest, then the manifest and the one after the upload")
    XCTAssertEqual(status, .connected(connectionID: "00000000-0000-7000-8000-000000000001"))
  }

  private func makeSync(_ server: FakeNotesServer, _ sleeps: Sleeps) -> (VaultChannelSync, RetryEventSource) {
    let source = RetryEventSource()
    let sync = VaultChannelSync(
      coordinator: { onChanges in
        VaultModeCoordinator(
          source: source, scanner: VaultScanner(root: self.vault), watcher: VaultWatcher(firstSequence: 1),
          now: { Date(timeIntervalSinceReferenceDate: 100) }, onChanges: onChanges
        )
      },
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture",
      retry: VaultChannelRetry(jitter: { 1 }, sleep: { sleeps.append($0) })
    )
    return (sync, source)
  }
}

/// Records each backoff delay and returns at once, in place of the clock.
private final class Sleeps: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [TimeInterval] = []

  var delays: [TimeInterval] { lock.withLock { stored } }

  func append(_ delay: TimeInterval) {
    lock.withLock { stored.append(delay) }
  }
}

private final class RetryEventSource: VaultEventSource, @unchecked Sendable {
  private var handler: (@Sendable ([String], Bool) -> Void)?

  func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {
    handler = onEvents
  }

  func stop() {}

  func emit(_ paths: [String]) {
    handler?(paths, false)
  }
}
