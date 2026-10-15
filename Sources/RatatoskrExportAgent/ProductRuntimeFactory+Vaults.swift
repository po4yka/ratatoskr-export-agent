import AgentCore
import Foundation

extension ProductRuntimeFactory {
  /// The watched Obsidian vaults, in `vault-preferences.json` of the support
  /// directory.
  static func makeVaultRegistry(support: URL) throws -> WatchedVaultRegistry {
    try WatchedVaultRegistry(
      store: FileWatchedVaultStore(fileURL: support.appending(path: "vault-preferences.json")),
      bookmarkStore: SecurityScopedBookmarkStore()
    )
  }

  /// One `VaultChannelSync` per watched vault, through the paired origin. The
  /// connection of each vault is saved in `vault-channels.json`.
  static func makeVaultComponent(
    support: URL, session: DeviceSessionCoordinator, registry: WatchedVaultRegistry
  ) -> VaultRuntimeComponent {
    let http = SessionBoundNotesChannelHTTP(session: session)
    let store = FileVaultChannelStateStore(fileURL: support.appending(path: "vault-channels.json"))
    return VaultRuntimeComponent(
      vaults: { await registry.runtimeVaults() },
      makeSync: { runtime in
        VaultChannelSync(
          coordinator: { onChanges in
            VaultModeCoordinator(
              source: FSEventsVaultEventSource(root: runtime.folder),
              scanner: VaultScanner(root: runtime.folder),
              watcher: VaultWatcher(
                firstSequence: 1,
                renameCheck: ObsidianCLIRenameCheck(vaultName: runtime.vault.displayName, runner: ProcessObsidianCLIRunner())
              ),
              onChanges: onChanges
            )
          },
          http: http, vault: runtime.folder, vaultKey: runtime.vault.vaultKey,
          vaultDisplayName: runtime.vault.displayName, stateStore: store
        )
      }
    )
  }
}
