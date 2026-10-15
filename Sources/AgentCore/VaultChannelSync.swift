import Foundation

/// Connects a watched vault to its `cli` channel: the manifest after the
/// connect, and the change batches after the manifest.
///
/// The coordinator gives its drained changes to a bounded buffer, and one
/// task gives everything that waits to the client in order; over the bound,
/// the task sends one manifest instead. That task starts only after the
/// first manifest, so no batch can go before it. The client keeps the changes that
/// a failed send leaves, and the task sends them again after the backoff of
/// `VaultChannelRetry`, without a new file event. A stopped channel (its
/// status) is not tried again.
public final class VaultChannelSync: @unchecked Sendable {
  public let coordinator: VaultModeCoordinator
  public let client: NotesChannelClient
  private let buffer: VaultChangeBuffer
  private let runner: VaultRetryRunner
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
    retry: VaultChannelRetry = VaultChannelRetry(),
    maximumBufferedChanges: Int = 10_000
  ) {
    let buffer = VaultChangeBuffer(limit: maximumBufferedChanges)
    self.buffer = buffer
    let made = coordinator { buffer.add($0) }
    self.coordinator = made
    client = NotesChannelClient(
      http: http, vault: vault, vaultKey: vaultKey, vaultDisplayName: vaultDisplayName,
      connectionID: connectionID, stateStore: stateStore, manifest: { made.manifest() }
    )
    runner = VaultRetryRunner(retry: retry, client: client)
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
    let sender = Task { [client, buffer, runner] in
      if startAgain {
        await runner.run(failed: 1, first: { try await client.start() }, again: { try await client.start() })
      }
      for await _ in buffer.signals {
        switch buffer.take() {
        case .changes(let list):
          await runner.run(first: { try await client.send(list) }, again: { try await client.send([]) })
        case .manifest:
          await runner.run(first: { try await client.resync() }, again: { try await client.resync() })
        case .nothing:
          continue
        }
      }
    }
    lock.withLock { self.sender = sender }
    if let failure {
      throw failure
    }
  }

  /// What the vault shows in the menu: stopped, retrying during a backoff,
  /// connected after an applied manifest, or connecting.
  public func status() async -> VaultSyncStatus {
    if case .stopped(let code) = await client.status {
      return .stopped(code: code)
    }
    if runner.isWaiting {
      return .retrying
    }
    return await client.isReady ? .connected : .connecting
  }

  /// Forgets the saved connection of a removed vault, and asks the send task
  /// to connect again and send the manifest.
  public func connectAgain() async {
    await client.connectAgain()
    buffer.requestManifest()
  }

  /// Stops the watcher and the sends.
  public func stop() {
    coordinator.stop()
    buffer.finish()
    lock.withLock {
      sender?.cancel()
      sender = nil
    }
  }
}
