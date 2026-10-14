import Foundation

/// Connects a watched vault to its `cli` channel: the manifest after the
/// connect, and the change batches after the manifest.
public final class VaultChannelSync: @unchecked Sendable {
  public let coordinator: VaultModeCoordinator
  public let client: NotesChannelClient

  /// `coordinator` makes the coordinator of the vault with the change sink
  /// that this type gives it.
  public init(
    coordinator: (@escaping @Sendable ([VaultChange]) -> Void) -> VaultModeCoordinator,
    http: any NotesChannelHTTP,
    vault: URL,
    vaultKey: String,
    vaultDisplayName: String,
    connectionID: String? = nil
  ) {
    self.coordinator = coordinator { _ in }
    client = NotesChannelClient(
      http: http, vault: vault, vaultKey: vaultKey, vaultDisplayName: vaultDisplayName,
      connectionID: connectionID, manifest: { VaultManifest(index: [:]) }
    )
  }

  /// Starts the watcher, connects, and sends the manifest.
  public func start(drainInterval: TimeInterval? = 0.5) async throws {}

  /// Stops the watcher and the sends.
  public func stop() {}
}
