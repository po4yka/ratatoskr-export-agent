import Foundation

/// The vault mode of the `cli` channel: the event source names paths, the
/// scanner reads the disk, and the watcher pairs renames and numbers the
/// changes. Final changes go to `onChanges` in sequence order.
///
/// The rename check can take up to 2 seconds, so the coordinator asks it at
/// most once per scan batch and never while it holds its lock. While the
/// check runs, `drain(at:)` gives nothing, so a waiting event cannot leave
/// before the batch that can pair it is recorded.
public final class VaultModeCoordinator: @unchecked Sendable {
  private let source: any VaultEventSource
  private let now: @Sendable () -> Date
  private let onChanges: @Sendable ([VaultChange]) -> Void
  private let lock = NSLock()
  private let observing = NSLock()
  private var checking = false
  private var scanner: VaultScanner
  private var watcher: VaultWatcher
  private var timer: DispatchSourceTimer?

  public init(
    source: any VaultEventSource,
    scanner: VaultScanner,
    watcher: VaultWatcher,
    now: @escaping @Sendable () -> Date = { Date() },
    onChanges: @escaping @Sendable ([VaultChange]) -> Void
  ) {
    self.source = source
    self.scanner = scanner
    self.watcher = watcher
    self.now = now
    self.onChanges = onChanges
  }

  /// Reads the whole vault and starts the event source. Returns the manifest
  /// (every indexed path with its fingerprint) that the device sends when it
  /// cannot prove that it saw every change. With a `drainInterval`, a timer
  /// delivers final changes; without one, the caller calls `drain(at:)`.
  @discardableResult
  public func start(drainInterval: TimeInterval? = 0.5) throws -> [String: ArchiveFingerprint] {
    let manifest = withLock {
      _ = scanner.rescan()
      return scanner.index
    }
    try source.start { [weak self] paths, rescan in
      self?.observe(paths: paths, rescan: rescan)
    }
    if let drainInterval {
      let created = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "ratatoskr.export-agent.vault-drain"))
      created.schedule(deadline: .now() + drainInterval, repeating: drainInterval)
      created.setEventHandler { [weak self] in
        self?.drain(at: self?.now() ?? Date())
      }
      created.resume()
      withLock { timer = created }
    }
    return manifest
  }

  /// Stops the event source and the timer; safe to call repeatedly.
  public func stop() {
    source.stop()
    withLock {
      timer?.cancel()
      timer = nil
    }
  }

  /// Compares the named paths with the disk and records what changed. Calls
  /// run one after the other, so batches are recorded in scan order.
  public func observe(paths: [String], rescan: Bool) {
    observing.withLock {
      let (observations, time, check) = withLock {
        let observations = rescan ? scanner.rescan() : scanner.scan(paths: paths)
        let time = now()
        checking = watcher.needsRenameCheck(observations, at: time)
        return (observations, time, checking ? watcher.renameCheck : nil)
      }
      let answer = check?.answer() ?? .unavailable
      withLock {
        for observation in observations {
          watcher.record(observation, at: time, answer: answer)
        }
        checking = false
      }
    }
  }

  /// Delivers the changes that are final at `time`.
  public func drain(at time: Date) {
    let changes = withLock { checking ? [] : watcher.drain(at: time) }
    if !changes.isEmpty {
      onChanges(changes)
    }
  }

  private func withLock<T>(_ work: () throws -> T) rethrows -> T {
    lock.lock()
    defer {
      lock.unlock()
    }
    return try work()
  }
}
