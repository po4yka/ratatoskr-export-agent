import Foundation

/// Runs a send or a start of the notes client again after the backoff of
/// `VaultChannelRetry`, and tells whether it waits in a backoff now.
final class VaultRetryRunner: @unchecked Sendable {
  private let retry: VaultChannelRetry
  private let client: NotesChannelClient
  private let lock = NSLock()
  private var waiting = false

  init(retry: VaultChannelRetry, client: NotesChannelClient) {
    self.retry = retry
    self.client = client
  }

  var isWaiting: Bool {
    lock.withLock { waiting }
  }

  /// Runs `first`, and after each failure waits the backoff and runs
  /// `again`, until one works, the channel is stopped, or the task is
  /// cancelled. `failed` counts the failures before this call: with one, the
  /// backoff comes before `first`. The client keeps the changes of a failed
  /// send, so `again` sends no new change.
  func run(
    failed: Int = 0,
    first: @escaping @Sendable () async throws -> Void,
    again: @escaping @Sendable () async throws -> Void
  ) async {
    defer {
      setWaiting(false)
    }
    var work = first
    var attempt = failed
    while !Task.isCancelled {
      if attempt > 0 {
        if case .stopped = await client.status {
          return
        }
        setWaiting(true)
        do {
          try await retry.wait(attempt: attempt)
        } catch {
          return
        }
      }
      do {
        try await work()
        return
      } catch {
        attempt += 1
        work = again
      }
    }
  }

  private func setWaiting(_ value: Bool) {
    lock.withLock { waiting = value }
  }
}
