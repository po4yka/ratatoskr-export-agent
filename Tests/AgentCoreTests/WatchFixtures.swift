import AgentCore
import Foundation
import XCTest

// Shared scripted fixtures for watcher behaviour tests. Internal on purpose:
// one definition per name across the AgentCoreTests module.

/// Virtual clock so quiet periods and debounce windows stay exact.
final class WatchVirtualClock: @unchecked Sendable {
  private let lock = NSLock()
  private var current: Date

  init(_ start: Date) {
    current = start
  }

  func advance(by interval: TimeInterval) {
    lock.lock()
    defer {
      lock.unlock()
    }
    current = current.addingTimeInterval(interval)
  }

  func date() -> Date {
    lock.lock()
    defer {
      lock.unlock()
    }
    return current
  }
}

/// Manual scheduler recording scheduled work for synchronous firing.
final class WatchManualScheduler: WatchScheduling, @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [(deadline: Date, work: @Sendable () -> Void)] = []

  var pendingCount: Int {
    lock.lock()
    defer {
      lock.unlock()
    }
    return entries.count
  }

  var firstDeadline: Date? {
    lock.lock()
    defer {
      lock.unlock()
    }
    return entries.first?.deadline
  }

  func scheduleWork(deadline: Date, work: @escaping @Sendable () -> Void) {
    lock.lock()
    defer {
      lock.unlock()
    }
    entries.append((deadline, work))
  }

  func cancelScheduledWork() {
    lock.lock()
    defer {
      lock.unlock()
    }
    entries.removeAll()
  }

  /// Runs everything currently scheduled, synchronously.
  func runPending() {
    lock.lock()
    let due = entries
    entries = []
    lock.unlock()
    for entry in due {
      entry.work()
    }
  }
}

/// Records which pieces of work executed, identified by tag.
final class WorkCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var ids: [Int] = []

  func record(_ id: Int) {
    lock.lock()
    defer {
      lock.unlock()
    }
    ids.append(id)
  }

  var recordedIDs: [Int] {
    lock.lock()
    defer {
      lock.unlock()
    }
    return ids
  }
}

/// Counts scan-pass completions reported by the coordinator.
final class PassCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func bump() {
    lock.lock()
    defer {
      lock.unlock()
    }
    count += 1
  }

  var value: Int {
    lock.lock()
    defer {
      lock.unlock()
    }
    return count
  }
}

/// Suspends until the pass counter reaches the target, yielding to the
/// actor between checks; fails cleanly instead of hanging.
func waitForPasses(
  _ target: Int,
  _ counter: PassCounter,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  for _ in 0..<100_000 {
    if counter.value >= target {
      return
    }
    await Task.yield()
  }
  XCTFail("scan passes did not reach \(target)", file: file, line: line)
}

/// Collects candidates delivered by the coordinator.
final class CandidateSink: @unchecked Sendable {
  private let lock = NSLock()
  private var received: [StableArchiveCandidate] = []

  var all: [StableArchiveCandidate] {
    lock.lock()
    defer {
      lock.unlock()
    }
    return received
  }

  func append(_ candidate: StableArchiveCandidate) {
    lock.lock()
    defer {
      lock.unlock()
    }
    received.append(candidate)
  }
}
