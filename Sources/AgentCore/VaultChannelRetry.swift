import Foundation

/// When `VaultChannelSync` tries a failed send or start again: the delay
/// doubles from `initialDelay` up to `maximumDelay`, and jitter takes off up
/// to half of it, so many agents do not try again at the same time. The
/// sleep is injected, so a test does not wait for the clock.
public struct VaultChannelRetry: Sendable {
  public let initialDelay: TimeInterval
  public let maximumDelay: TimeInterval
  private let jitter: @Sendable () -> Double
  private let sleep: @Sendable (TimeInterval) async throws -> Void

  public init(
    initialDelay: TimeInterval = 5,
    maximumDelay: TimeInterval = 300,
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { delay in
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
  ) {
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
    self.jitter = jitter
    self.sleep = sleep
  }

  /// The delay before try `attempt` again, the first is 1.
  public func delay(attempt: Int) -> TimeInterval {
    let backoff = min(maximumDelay, initialDelay * pow(2, Double(max(0, attempt - 1))))
    return backoff / 2 + backoff / 2 * min(1, max(0, jitter()))
  }

  /// Waits the delay of `attempt`. Throws when the task is cancelled.
  func wait(attempt: Int) async throws {
    try await sleep(delay(attempt: attempt))
  }
}
