import AgentCore
import AppKit
import Foundation

extension ProductRuntimeFactory {
  /// The grant of the owner to read `obsidian.json`, a bookmark in
  /// `obsidian-config.bookmark` of the support directory.
  static func makeObsidianGrant(support: URL) -> ObsidianConfigGrant {
    ObsidianConfigGrant(
      bookmarkFile: support.appending(path: "obsidian-config.bookmark"), bookmarkStore: SecurityScopedBookmarkStore()
    )
  }

  /// The watched Obsidian vaults, in `vault-preferences.json` of the support
  /// directory. The key of a vault comes from `obsidian.json`, read directly
  /// or through the grant of the owner.
  static func makeVaultRegistry(support: URL, grant: ObsidianConfigGrant) throws -> WatchedVaultRegistry {
    try WatchedVaultRegistry(
      store: FileWatchedVaultStore(fileURL: support.appending(path: "vault-preferences.json")),
      bookmarkStore: SecurityScopedBookmarkStore(),
      vaultKey: { ObsidianVaultKey.key(forVault: $0, config: ObsidianVaultKey.userConfig) ?? grant.key(forVault: $0) }
    )
  }

  /// The apply step of the queued writes of a vault. A write can make
  /// Obsidian update the links of many files, so the CLI has 30 seconds.
  nonisolated static func makeOperations(_ runtime: RuntimeVault) -> ObsidianCLIApply {
    ObsidianCLIApply(
      vault: runtime.folder, vaultName: runtime.vault.displayName, runner: ProcessObsidianCLIRunner(timeLimit: 30),
      obsidianRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: ObsidianCLIApply.bundleIdentifier).isEmpty }
    )
  }

  /// One `VaultChannelSync` per watched vault, through the paired origin. The
  /// connection of each vault is saved in `vault-channels.json`, and the
  /// results that notes did not take yet in `device-results.json`.
  static func makeVaultComponent(
    support: URL, session: DeviceSessionCoordinator, registry: WatchedVaultRegistry
  ) -> VaultRuntimeComponent {
    let http = SessionBoundNotesChannelHTTP(session: session)
    let store = FileVaultChannelStateStore(fileURL: support.appending(path: "vault-channels.json"))
    let results = FileDeviceResultStore(fileURL: support.appending(path: "device-results.json"))
    return VaultRuntimeComponent(
      vaults: {
        _ = await registry.adoptObsidianKeys(clearing: store)
        return await registry.runtimeVaults()
      },
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
          vaultDisplayName: runtime.vault.displayName, stateStore: store, resultStore: results,
          operations: makeOperations(runtime)
        )
      }
    )
  }
}
