import AgentCore
import CryptoKit
import XCTest

/// The status of a vault whose queued writes wait for the Obsidian app.
final class VaultSyncObsidianStatusTests: XCTestCase {
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

  func testAPassThatWaitsForObsidianShowsInTheStatus() async throws {
    let server = FakeNotesServer()
    scriptQueue(server)
    let app = AppSwitch()
    let apply = ObsidianCLIApply(
      vault: vault, vaultName: "Fixture", runner: AnsweringRunner(), obsidianRunning: { app.running }, settle: {}
    )
    let sync = VaultChannelSync(
      coordinator: { onChanges in
        VaultModeCoordinator(
          source: SilentEventSource(), scanner: VaultScanner(root: self.vault), watcher: VaultWatcher(firstSequence: 1),
          now: { Date(timeIntervalSinceReferenceDate: 100) }, onChanges: onChanges
        )
      },
      http: server, vault: vault, vaultKey: "vault-key-1", vaultDisplayName: "Fixture",
      operations: apply, queueInterval: 3600
    )

    try await sync.start(drainInterval: nil)
    var closed = await sync.status()
    for _ in 0..<200 where closed != .awaitingObsidian {
      try await Task.sleep(nanoseconds: 10_000_000)
      closed = await sync.status()
    }
    app.running = true
    scriptQueue(server)
    server.script("/content", status: 200, body: "beta")
    server.script("/result", status: 200, body: #"{"operation_id":"00000000-0000-7000-8000-0000000000b1","state":"succeeded"}"#)
    let pass = try await sync.client.applyQueuedOperations(apply)
    let open = await sync.status()
    sync.stop()

    XCTAssertEqual(closed, .awaitingObsidian, "an operation waits and the app does not run")
    XCTAssertEqual(pass, .answered(1))
    XCTAssertEqual(open, .connected, "a pass while the app runs ends the wait")
  }

  private func scriptQueue(_ server: FakeNotesServer) {
    let alpha = SHA256.hash(data: Data("alpha".utf8)).map { String(format: "%02x", $0) }.joined()
    let beta = SHA256.hash(data: Data("beta".utf8)).map { String(format: "%02x", $0) }.joined()
    let operation =
      #"{"operation_id":"00000000-0000-7000-8000-0000000000b1","cursor":"1","kind":"update","path":"A.md","target_path":null,"#
      + #""base_hash":"\#(alpha)","content":{"owner_service":"ratatoskr-notes","digest":{"algorithm":"sha256","hex":"\#(beta)"},"#
      + #""media_type":"text/markdown","length_bytes":4},"property_key":null,"property_change":null,"expected_sha256":null}"#
    server.script("/device-operations", status: 200, body: #"{"operations":[\#(operation)],"next_cursor":"1"}"#)
  }
}

private final class AppSwitch: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var running: Bool {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }
}

private struct AnsweringRunner: ObsidianCLIRunning {
  func run(_ arguments: [String]) -> ObsidianCLIAnswer? {
    ObsidianCLIAnswer(status: 0, output: "1.12.7")
  }
}

private final class SilentEventSource: VaultEventSource, @unchecked Sendable {
  func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {}
  func stop() {}
}
