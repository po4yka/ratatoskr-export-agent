import Foundation

/// Scheduling seam for debounce windows and stability re-assessments, so
/// timing behaviour is testable with a manual scheduler instead of real
/// dispatch queues.
public protocol WatchScheduling: AnyObject, Sendable {
  /// Schedules the work to run at the given wall-clock deadline.
  func scheduleWork(deadline: Date, work: @escaping @Sendable () -> Void)

  /// Cancels every currently scheduled piece of work.
  func cancelScheduledWork()
}

/// Collapses bursts of triggers into a single firing at the end of the
/// window, measured from the most recent trigger.
public struct Debouncer: Sendable {
  private let window: TimeInterval
  private let scheduler: any WatchScheduling
  private let now: @Sendable () -> Date

  public init(
    window: TimeInterval, scheduler: any WatchScheduling, now: @escaping @Sendable () -> Date
  ) {
    self.window = window
    self.scheduler = scheduler
    self.now = now
  }

  /// Registers a trigger; replaces any pending firing.
  public mutating func trigger(work: @escaping @Sendable () -> Void) {
    scheduler.cancelScheduledWork()
    scheduler.scheduleWork(deadline: now().addingTimeInterval(window), work: work)
  }
}

/// Dispatch-queue-backed scheduler for production use.
public final class DispatchWatchScheduler: WatchScheduling, @unchecked Sendable {
  private let queue: DispatchQueue
  private let lock = NSLock()
  private var scheduledItems: [DispatchWorkItem] = []

  /// Creates a scheduler delivering on its own serial queue.
  public init(queue: DispatchQueue = DispatchQueue(label: "ratatoskr.export-agent.watch")) {
    self.queue = queue
  }

  public func scheduleWork(deadline: Date, work: @escaping @Sendable () -> Void) {
    let item = DispatchWorkItem(block: work)
    lock.lock()
    scheduledItems.append(item)
    lock.unlock()
    queue.asyncAfter(deadline: .now() + deadline.timeIntervalSinceNow, execute: item)
  }

  public func cancelScheduledWork() {
    lock.lock()
    let items = scheduledItems
    scheduledItems.removeAll()
    lock.unlock()
    for item in items {
      item.cancel()
    }
  }
}
