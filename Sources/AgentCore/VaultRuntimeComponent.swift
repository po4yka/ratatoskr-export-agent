import Foundation

/// A watched vault with the folder that its bookmark resolves to.
public struct RuntimeVault: Equatable, Sendable {
  public let vault: WatchedVault
  public let folder: URL

  public init(vault: WatchedVault, folder: URL) {
    self.vault = vault
    self.folder = folder
  }
}

/// What the runtime does with the sync of one vault.
public protocol VaultSyncing: Sendable {
  /// Starts the sync without waiting for the network.
  func launch()
  func stop()
}

/// Runs one `VaultChannelSync` for each watched vault.
public actor VaultRuntimeComponent: OperationalRuntimeComponent {
  public init(
    vaults: @escaping @Sendable () async -> [RuntimeVault],
    makeSync: @escaping @Sendable (RuntimeVault) -> any VaultSyncing
  ) {}

  public func start() async {}
  public func reconcile() async {}
  public func stop() async {}
}
