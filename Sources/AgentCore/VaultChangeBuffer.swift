import Foundation

/// The drained changes that wait for the send task of `VaultChannelSync`, at
/// most `limit`. A long outage cannot fill memory: over the limit the buffer
/// drops its changes and asks for one manifest, which describes the whole
/// vault and so covers them.
final class VaultChangeBuffer: @unchecked Sendable {
  enum Taken: Equatable {
    case changes([VaultChange])
    case manifest
    case nothing
  }

  /// One signal waits at most, so the signals are bounded too.
  let signals: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation
  private let limit: Int
  private let lock = NSLock()
  private var changes: [VaultChange] = []
  private var overflowed = false

  init(limit: Int) {
    self.limit = limit
    (signals, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
  }

  func add(_ list: [VaultChange]) {
    lock.withLock {
      guard !overflowed else {
        return
      }
      changes += list
      if changes.count > limit {
        changes.removeAll()
        overflowed = true
      }
    }
    continuation.yield()
  }

  /// Everything that waits: the changes in drain order, or a manifest after
  /// an overflow.
  func take() -> Taken {
    lock.withLock {
      if overflowed {
        overflowed = false
        return .manifest
      }
      defer {
        changes.removeAll()
      }
      return changes.isEmpty ? .nothing : .changes(changes)
    }
  }

  func finish() {
    continuation.finish()
  }
}
