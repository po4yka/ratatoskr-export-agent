import Foundation

/// When `VaultChannelSync` tries a failed send or start again.
public struct VaultChannelRetry: Sendable {
  public let initialDelay: TimeInterval
  public let maximumDelay: TimeInterval
  private let jitter: @Sendable () -> Double
  private let sleep: @Sendable (TimeInterval) async throws -> Void

  public init(
    initialDelay: TimeInterval = 5,
    maximumDelay: TimeInterval = 300,
    jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void
  ) {
    self.initialDelay = initialDelay
    self.maximumDelay = maximumDelay
    self.jitter = jitter
    self.sleep = sleep
  }

  /// The delay before try `attempt` again, the first is 1.
  public func delay(attempt: Int) -> TimeInterval {
    0
  }
}
