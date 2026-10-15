import Foundation

/// Connects a watched vault to its `cli` channel: the manifest after the
/// connect, and the change batches after the manifest.
///
/// The coordinator gives its drained changes to a stream, and one task gives
/// them to the client in order. That task starts only after the first
/// manifest, so no batch can go before it. The client keeps the changes that
/// a failed send leaves, and the task sends them again after the backoff of
/// `VaultChannelRetry`, without a new file event. A stopped channel (its
/// status) is not tried again.
public final class VaultChannelSync: @unchecked Sendable {
  public let coordinator: VaultModeCoordinator
  public let client: NotesChannelClient
  private let changes: AsyncStream<[VaultChange]>
  private let continuation: AsyncStream<[VaultChange]>.Continuation
  private let retry: VaultChannelRetry
  private let lock = NSLock()
  private var sender: Task<Void, Never>?

  /// `coordinator` makes the coordinator of the vault with the change sink
  /// that this type gives it.
  public init(
    coordinator: (@escaping @Sendable ([VaultChange]) -> Void) -> VaultModeCoordinator,
    http: any NotesChannelHTTP,
    vault: URL,
    vaultKey: String,
    vaultDisplayName: String,
    connectionID: String? = nil,
    stateStore: (any VaultChannelStateStoring)? = nil,
    retry: VaultChannelRetry = VaultChannelRetry()
  ) {
    self.retry = retry
    (changes, continuation) = AsyncStream.makeStream(of: [VaultChange].self)
    let continuation = continuation
    let made = coordinator { continuation.yield($0) }
    self.coordinator = made
    client = NotesChannelClient(
      http: http, vault: vault, vaultKey: vaultKey, vaultDisplayName: vaultDisplayName,
      connectionID: connectionID, stateStore: stateStore, manifest: { made.manifest() }
    )
  }

  /// Starts the watcher, connects, and sends the manifest. When the start of
  /// the client fails, the send task tries it again after the backoff, and
  /// the error goes to the caller.
  public func start(drainInterval: TimeInterval? = 0.5) async throws {
    try coordinator.start(drainInterval: drainInterval)
    var failure: (any Error)?
    do {
      try await client.start()
    } catch {
      failure = error
    }
    let startAgain = failure != nil
    let sender = Task { [client, changes, retry] in
      if startAgain {
        await Self.retrying(retry, client, failed: 1, first: { try await client.start() }, again: { try await client.start() })
      }
      for await list in changes {
        await Self.retrying(retry, client, first: { try await client.send(list) }, again: { try await client.send([]) })
      }
    }
    lock.withLock { self.sender = sender }
    if let failure {
      throw failure
    }
  }

  /// Stops the watcher and the sends.
  public func stop() {
    coordinator.stop()
    continuation.finish()
    lock.withLock {
      sender?.cancel()
      sender = nil
    }
  }

  /// Runs `first`, and after each failure waits the backoff and runs
  /// `again`, until one works, the channel is stopped, or the task is
  /// cancelled. `failed` counts the failures before this call: with one, the
  /// backoff comes before `first`. The client keeps the changes of a failed
  /// send, so `again` sends no new change.
  private static func retrying(
    _ retry: VaultChannelRetry,
    _ client: NotesChannelClient,
    failed: Int = 0,
    first: @escaping @Sendable () async throws -> Void,
    again: @escaping @Sendable () async throws -> Void
  ) async {
    var work = first
    var attempt = failed
    while !Task.isCancelled {
      if attempt > 0 {
        if case .stopped = await client.status {
          return
        }
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
}
