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
  func status() async -> VaultSyncStatus
  /// Forgets the saved connection of a removed vault and connects again.
  func connectAgain() async
}

/// Runs one `VaultChannelSync` for each watched vault. A reconcile reads the
/// vaults again: it stops the sync of a vault that is gone or whose folder
/// moved, and launches the sync of a new vault.
public actor VaultRuntimeComponent: OperationalRuntimeComponent {
  private let vaults: @Sendable () async -> [RuntimeVault]
  private let makeSync: @Sendable (RuntimeVault) -> any VaultSyncing
  private var running: [(vault: RuntimeVault, sync: any VaultSyncing)] = []

  public init(
    vaults: @escaping @Sendable () async -> [RuntimeVault],
    makeSync: @escaping @Sendable (RuntimeVault) -> any VaultSyncing
  ) {
    self.vaults = vaults
    self.makeSync = makeSync
  }

  public func start() async {
    await reconcile()
  }

  public func reconcile() async {
    let wanted = await vaults()
    for entry in running where !wanted.contains(entry.vault) {
      entry.sync.stop()
    }
    running.removeAll { !wanted.contains($0.vault) }
    for vault in wanted where !running.contains(where: { $0.vault == vault }) {
      let sync = makeSync(vault)
      sync.launch()
      running.append((vault, sync))
    }
  }

  public func stop() async {
    for entry in running {
      entry.sync.stop()
    }
    running.removeAll()
  }

  /// The status of each running vault, in the order of the vaults.
  public func statusRows() async -> [VaultStatusRow] {
    var rows: [VaultStatusRow] = []
    for entry in running {
      let vault = entry.vault.vault
      rows.append(VaultStatusRow(id: vault.id, displayName: vault.displayName, status: await entry.sync.status()))
    }
    return rows
  }

  /// Connects a vault whose connection the owner removed again.
  public func connectAgain(id: UUID) async {
    await running.first { $0.vault.vault.id == id }?.sync.connectAgain()
  }
}

extension VaultChannelSync: VaultSyncing {
  /// Starts the sync in a task: the connect and the manifest can take long,
  /// and a failed start is tried again by the sync itself.
  public func launch() {
    Task {
      try? await start()
    }
  }
}
