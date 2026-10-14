import AgentCore
import XCTest

final class VaultModeCoordinatorTests: XCTestCase {
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

  func testOutsideRenameReachesTheBatchAsOneRenamedChange() throws {
    let source = ScriptedVaultEventSource()
    let clock = VaultClock()
    let sink = ChangeSink()
    let coordinator = VaultModeCoordinator(
      source: source,
      scanner: VaultScanner(root: vault),
      watcher: VaultWatcher(firstSequence: 31),
      now: { clock.now },
      onChanges: { sink.append($0) }
    )

    let manifest = try coordinator.start(drainInterval: nil)
    try FileManager.default.moveItem(at: vault.appendingPathComponent("A.md"), to: vault.appendingPathComponent("B.md"))
    source.emit([vault.appendingPathComponent("B.md").path], rescan: false)
    clock.now = clock.now.addingTimeInterval(1)
    source.emit([vault.appendingPathComponent("A.md").path], rescan: false)
    coordinator.drain(at: clock.now.addingTimeInterval(3))
    coordinator.stop()

    XCTAssertEqual(Array(manifest.keys), ["A.md"])
    XCTAssertEqual(
      sink.changes,
      [VaultChange(sequence: 31, kind: .renamed, path: "B.md", previousPath: "A.md", sha256: manifest["A.md"]?.sha256Hex, byteLength: 5)]
    )
    XCTAssertTrue(source.stopped)
  }

  func testLostEventsRescanTheVault() throws {
    let source = ScriptedVaultEventSource()
    let sink = ChangeSink()
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let coordinator = VaultModeCoordinator(
      source: source,
      scanner: VaultScanner(root: vault),
      watcher: VaultWatcher(firstSequence: 1),
      now: { start },
      onChanges: { sink.append($0) }
    )
    try coordinator.start(drainInterval: nil)

    try Data("beta".utf8).write(to: vault.appendingPathComponent("A.md"))
    source.emit([], rescan: true)
    coordinator.drain(at: start)

    XCTAssertEqual(sink.changes.map(\.kind), [.updated])
  }
}

private final class ScriptedVaultEventSource: VaultEventSource, @unchecked Sendable {
  private var handler: (@Sendable ([String], Bool) -> Void)?
  private(set) var stopped = false

  func start(onEvents: @escaping @Sendable ([String], Bool) -> Void) throws {
    handler = onEvents
  }

  func stop() {
    stopped = true
  }

  func emit(_ paths: [String], rescan: Bool) {
    handler?(paths, rescan)
  }
}

private final class VaultClock: @unchecked Sendable {
  var now = Date(timeIntervalSinceReferenceDate: 100)
}

private final class ChangeSink: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [VaultChange] = []

  var changes: [VaultChange] {
    lock.withLock { stored }
  }

  func append(_ changes: [VaultChange]) {
    lock.withLock { stored += changes }
  }
}
