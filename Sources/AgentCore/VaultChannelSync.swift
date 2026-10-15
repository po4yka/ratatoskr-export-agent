import Foundation

/// Connects a watched vault to its `cli` channel: the manifest after the
/// connect, and the change batches after the manifest.
///
/// The coordinator gives its drained changes to a stream, and one task gives
/// them to the client in order. That task starts only after the first
/// manifest, so no batch can go before it. The client keeps the changes that
/// a failed send leaves and sends them with the next changes; its status
/// shows a stopped channel.
public final class VaultChannelSync: @unchecked Sendable {
  public let coordinator: VaultModeCoordinator
  public let client: NotesChannelClient
  private let changes: AsyncStream<[VaultChange]>
  private let continuation: AsyncStream<[VaultChange]>.Continuation
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
    retry: VaultChannelRetry = VaultChannelRetry(sleep: { _ in })
  ) {
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
  /// the client fails, the changes still go to the client, which starts
  /// again before it sends them.
  public func start(drainInterval: TimeInterval? = 0.5) async throws {
    try coordinator.start(drainInterval: drainInterval)
    defer {
      let sender = Task { [client, changes] in
        for await list in changes {
          try? await client.send(list)
        }
      }
      lock.withLock { self.sender = sender }
    }
    try await client.start()
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
}
