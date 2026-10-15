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
  private var stopped = false

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
  /// A stopped sync does not start again: `stop()` can run before the task
  /// of `launch()`, and then nothing may start.
  public func start(drainInterval: TimeInterval? = 0.5) async throws {
    guard !isStopped else {
      return
    }
    try coordinator.start(drainInterval: drainInterval)
    guard !isStopped else {
      coordinator.stop()
      return
    }
    var failure: (any Error)?
    do {
      try await client.start()
    } catch {
      failure = error
    }
    guard keep(sendTask(startAgain: failure != nil)) else {
      coordinator.stop()
      return
    }
    if let failure {
      throw failure
    }
  }

  /// The task that gives the waiting changes to the client, after a start
  /// again when the first start failed.
  private func sendTask(startAgain: Bool) -> Task<Void, Never> {
    Task { [client, buffer, runner] in
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
  }

  /// Keeps the send task, or cancels it when a stop came first.
  private func keep(_ task: Task<Void, Never>) -> Bool {
    let kept = lock.withLock {
      guard !stopped else {
        return false
      }
      sender = task
      return true
    }
    if !kept {
      task.cancel()
    }
    return kept
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
      stopped = true
      sender?.cancel()
      sender = nil
    }
  }

  private var isStopped: Bool {
    lock.withLock { stopped }
  }
}
