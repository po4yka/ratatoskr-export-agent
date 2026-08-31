import AgentCore
import Foundation
import XCTest

/// Bundles scripted metadata, manual schedulers, a virtual clock, and a
/// candidate sink into one coordinator harness for watcher tests.
final class WatchScenario: @unchecked Sendable {
  private struct FixtureGone: Error {}

  let metadata = ScriptedFolderMetadata()
  let debounceScheduler = WatchManualScheduler()
  let tickScheduler = WatchManualScheduler()
  let clock = WatchVirtualClock(Date(timeIntervalSinceReferenceDate: 3_000_000))
  let sink = CandidateSink()

  private let lock = NSLock()
  private var monitorsByID: [UUID: ScriptedInboxMonitor] = [:]
  private var requestedIDs: [UUID] = []
  private var startFailuresByID: [UUID: Error] = [:]

  /// Synthetic folder location; nothing here touches the real filesystem.
  static func folderURL(named name: String) -> URL {
    URL(fileURLWithPath: "/watch-fixture/\(name)")
  }

  func addCandidate(named fileName: String, in folder: URL, byteSize: Int) -> URL {
    let url = folder.appendingPathComponent(fileName)
    metadata.registerCandidate(url, byteSize: byteSize, modifiedAt: clock.date())
    return url
  }

  func failListing(of folder: URL, code: CocoaError.Code) {
    metadata.failListings(of: folder, with: CocoaError(code))
  }

  func failMonitorStart(_ error: Error, for id: UUID) {
    lock.lock()
    defer {
      lock.unlock()
    }
    startFailuresByID[id] = error
  }

  func makeCoordinator(
    targets: [WatchedFolderTarget],
    onScanPass: @escaping @Sendable () -> Void = {}
  ) -> InboxWatchCoordinator {
    makeCoordinator(
      targets: targets,
      candidateHandler: { [sink] in
        sink.append($0)
        return true
      },
      onScanPass: onScanPass
    )
  }

  func makeCoordinator(
    targets: [WatchedFolderTarget],
    candidateHandler: @escaping @Sendable (StableArchiveCandidate) async -> Bool,
    onScanPass: @escaping @Sendable () -> Void = {}
  ) -> InboxWatchCoordinator {
    InboxWatchCoordinator(
      targets: targets,
      monitorFactory: { [weak self] target in
        guard let self else {
          throw FixtureGone()
        }
        return try self.monitor(for: target)
      },
      metadata: metadata,
      debounceScheduler: debounceScheduler,
      tickScheduler: tickScheduler,
      configuration: CoordinatorConfiguration(
        debounceWindow: 0.5,
        quietInterval: 30,
        maxArchiveBytes: 1_000_000
      ),
      clock: { [clock] in
        clock.date()
      },
      onCandidate: candidateHandler,
      onScanPassFinished: onScanPass
    )
  }

  func requestedTargetIDs() -> [UUID] {
    lock.lock()
    defer {
      lock.unlock()
    }
    return requestedIDs
  }

  func monitor(for id: UUID) -> ScriptedInboxMonitor? {
    lock.lock()
    defer {
      lock.unlock()
    }
    return monitorsByID[id]
  }

  private func monitor(for target: WatchedFolderTarget) throws -> ScriptedInboxMonitor {
    lock.lock()
    defer {
      lock.unlock()
    }
    requestedIDs.append(target.id)
    let monitor = ScriptedInboxMonitor(startFailure: startFailuresByID[target.id])
    monitorsByID[target.id] = monitor
    return monitor
  }
}
