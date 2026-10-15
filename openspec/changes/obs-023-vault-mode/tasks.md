## 1. Rename pairing (workspace OBS-023 tasks 12.1 and 12.2)

- [x] 1.1 RED: `Tests/AgentCoreTests/VaultWatcherTests.swift` `testDeleteAndCreateWithEqualHashIsRename` feeds a delete and a create with equal hashes and asserts one `renamed` change. Confirm that it fails because the vault watcher does not exist (a stub that returns no change, so the failure is the assertion and not a compile error).
- [x] 1.2 GREEN: implement the vault mode with FSEvents, the Obsidian CLI rename check, and the same batch format as the plugin. Verify 1.1.

## 2. Gate

- [x] 2.1 Run `swift build`, `swift test`, `swift build -c release`, the release `--smoke` launch, `Tests/Distribution/run.sh`, `swiftlint`, and `openspec validate --all --strict`. A gate run is not a behaviour and cannot start from a failing test. `openspec validate --all --strict` also fails on `main` for three items that this change does not touch (two specs and `xr-021-r5-classify-platform-answers`, a requirement longer than 500 characters); `obs-023-vault-mode` is valid.

## 3. Pairing order and one rename check per batch (workspace OBS-023 tasks 12.3 and 12.4)

- [x] 3.1 RED: `Tests/AgentCoreTests/VaultWatcherTests.swift` `testFolderRenameOfIdenticalFilesKeepsEachPathPair` (a folder rename of files with identical content pairs Old/X with New/X by the file name, never across names), `testSamePathIsPreferredOverAnotherPathWithTheSameHash`, and `testCreateThenDeleteInsideWindowSendsNothing`; `Tests/AgentCoreTests/VaultModeCoordinatorTests.swift` `testFolderRenameAsksTheRenameCheckAtMostOnce` (a folder rename of 3 files runs the fake CLI at most once per scan batch, and never while the coordinator lock is held). The first, the second and the fourth fail by their assertions; the third passes before the change, because a path created and deleted inside the window already pairs with itself.
- [x] 3.2 GREEN: pairing prefers the same file name under the renamed folder, then the same path, then the nearest equal-hash path. The coordinator asks the rename check once per scan batch outside its lock and uses that answer for every pair of the batch. Keep the 2 s limit and the 60 s quiet period. Verify 3.1 and the full suite.
- [x] 3.3 Run the gates of `ci.yml`: `swift build`, `swift test`, `swift build -c release`, the release `--smoke` launch, `Tests/Distribution/run.sh` and `swiftlint`, and run the real-FSEvents test 3 times. A gate run is not a behaviour and cannot start from a failing test.

## 4. Wire types of the notes routes (workspace OBS-023 tasks 12.5 and 12.6)

- [x] 4.1 RED: `Tests/AgentCoreTests/VaultChangeBatchTests.swift` `testRenamedChangeHasPluginKeys` expects the key `length_bytes` in place of `byte_length`, and `Tests/AgentCoreTests/VaultManifestTests.swift` `testManifestOfTheScanHasTheNotesKeysInPathOrder` expects the manifest of a vault scan as `{"entries":[{"length_bytes","path","sha256"}]}` in path order, with the empty file. Confirm that both fail by their assertions (a `VaultManifest` stub gives no entries).
- [x] 4.2 GREEN: `VaultChange` encodes `length_bytes`, and `VaultManifest(index:)` makes one entry for each indexed path, in path order. Verify 4.1 and the full suite.

## 5. Notes channel client (workspace OBS-023 tasks 12.7 and 12.8)

- [x] 5.1 RED: with the fake HTTP transport `Tests/AgentCoreTests/FakeNotesServer.swift`, `NotesChannelClientTests` asserts that a start connects with channel `cli`, sends the manifest, uploads the bytes that it needs in 1 MiB chunks and sends the manifest again, that changes continue the committed sequence of the manifest answer, that a `404` `notes.connection.not_found` connects again and sends the manifest, and that `notes.channel_mismatch` stops the channel and surfaces it in the status; `NotesChannelBatchTests` asserts that `notes.channel.sequence_gap` sends again from the committed sequence plus 1, that `notes.channel.bytes_missing` uploads those hashes and sends the batch again (the empty file has no upload), that `notes.channel.batch_too_large` splits the batch, and that 257 changes go as 256 and 1; `NotesChannelHTTPTests` asserts that the HTTPS binding sends the device credential to the Edge path. Confirm that all fail by their assertions (a client stub sends nothing).
- [x] 5.2 GREEN: implement `NotesChannelClient`, the blob transport of the notes routes on the existing `ResumableArchiveUploader` with 1 MiB chunks, and `PlatformNotesChannelHTTP`. Verify 5.1 and the full suite.

## 6. A watched vault sends to notes (workspace OBS-023 tasks 12.9 and 12.10)

- [x] 6.1 RED: `Tests/AgentCoreTests/VaultChannelSyncTests.swift` `testWatchedVaultSendsItsManifestAfterTheConnectAndItsBatchesAfter` starts a `VaultChannelSync` on a temporary vault with a scripted event source and the fake notes transport, creates `B.md`, drains, and asserts the order connect, manifest (with `A.md`), manifest, change batch `[1]`, and that a stop stops the event source. Confirm that it fails by its assertions (a `VaultChannelSync` stub sends nothing).
- [x] 6.2 GREEN: `VaultChannelSync` starts the coordinator, starts the client (connect and manifest of the coordinator index), and then gives each drained change list to the client in order through one task. Verify 6.1 and the full suite.

## 7. Gate (after workspace OBS-023 task 12.10)

- [x] 7.1 Run the gates of `ci.yml` (`swift build`, `swift test`, `swift build -c release`, the release `--smoke` launch, `Tests/Distribution/run.sh`, `swiftlint`, the DEVELOPMENT.md drift check), the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-023-vault-mode --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 8. A removed connection stops the channel (workspace OBS-023 tasks 12.11 and 12.12)

- [x] 8.1 RED: `Tests/AgentCoreTests/NotesChannelRemovedTests.swift` asserts that a `410` `notes.connection.removed` on a change batch, and on an upload, stops the channel like `notes.channel_mismatch`: the error is `connectionRemoved`, the status is `stopped(code: "notes.connection.removed")`, the waiting changes are cleared, a later send or start makes no request, and the agent does not connect again. Confirm that both tests fail by their assertions (the answer is `refused(status: 410, ...)` and the channel stays connected).
- [x] 8.2 GREEN: map `410` `notes.connection.removed` on every device route to `connectionRemoved`, and stop the channel on it as on `channelMismatch`. Verify 8.1 and the full suite.

## 9. A restart resumes the saved connection (workspace OBS-023 tasks 12.13 and 12.14)

- [x] 9.1 RED: `Tests/AgentCoreTests/NotesChannelStateTests.swift` asserts that a second client with the same `FileVaultChannelStateStore` resumes the saved connection with the manifest first and continues its sequence, that a saved connection that answers `404` `notes.connection.not_found` connects again and saves the new connection, and that the state file holds only `vault_key`, `connection_id` and `committed_sequence`. Confirm that all 3 fail by their assertions (a store stub saves nothing and loads nothing).
- [x] 9.2 GREEN: `FileVaultChannelStateStore` keeps the state of each vault in one JSON file, written atomically; the client loads it before its first connect and saves it after a connect, an applied manifest and a committed batch. Verify 9.1 and the full suite.

## 10. A failed send is tried again by a timer (workspace OBS-023 tasks 12.17 and 12.18)

- [x] 10.1 RED: `Tests/AgentCoreTests/VaultChannelRetryTests.swift` asserts that the retry delay doubles from 5 seconds to at most 5 minutes and that jitter takes off at most half of it, that a failed send is sent again after the backoff (5 s, then 10 s, through an injected sleep) without a new file event, and that a failed start is tried again by the same timer. Confirm that all 3 fail by their assertions (a `VaultChannelRetry` stub gives 0 and the sync does not try again).
- [x] 10.2 GREEN: `VaultChannelRetry` gives the delay with jitter, and the send task of `VaultChannelSync` tries a failed start or send again after it, until it works, the channel is stopped, or the sync stops. Verify 10.1 and the full suite.

## 11. Gate (after workspace OBS-023 task 12.18)

- [x] 11.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-023-vault-mode --strict`. A gate run is not a behaviour and cannot start from a failing test. Workspace tasks 12.15 and 12.16 (the vault mode in the app configuration and start) are not done here: no settings surface or runtime component for a vault exists yet.

## 12. The vault key of the plugin (workspace OBS-023 tasks 12.15 and 12.16)

- [x] 12.1 RED: `Tests/AgentCoreTests/ObsidianVaultKeyTests.swift` reads a fixture `obsidian.json` in a temporary directory and asserts that the key of a vault is its vault id of Obsidian (the `app.appId` that the plugin sends as `vault_key`), also for a path with a trailing slash and for a linked path, and that an unknown vault, a missing file and an invalid file give no key. Confirm that the first two fail by their assertions (a stub gives no key); the third passes before the change, because the stub gives no key for every input.
- [x] 12.2 GREEN: `ObsidianVaultKey.key(forVault:config:)` finds the entry of `vaults` in `obsidian.json` whose `path` is the vault path after both resolve their links. Verify 12.1 and the full suite.

## 13. Vault registry and settings (workspace OBS-023 tasks 12.19 and 12.20)

- [x] 13.1 RED: `Tests/AgentCoreTests/WatchedVaultRegistryTests.swift` asserts that an added vault has the vault id of Obsidian as its key, the folder name as its display name and its bookmark, and is saved in `vault-preferences.json`; that a vault without a vault id of Obsidian gets a generated key once, and the same folder is one vault; and that a removed vault is gone after a reload. `Tests/RatatoskrExportAgentTests/VaultSettingsViewModelTests.swift` asserts that the settings add a vault from the folder picker, show it by name, and remove it. Confirm that all fail by their assertions (stubs store nothing).
- [x] 13.2 GREEN: `WatchedVaultRegistry` with `FileWatchedVaultStore`, and `VaultSettingsViewModel` with a vault section in the settings window. Verify 13.1 and the full suite.

## 14. A bounded buffer of changes (workspace OBS-023 tasks 12.21 and 12.22)

- [x] 14.1 RED: `Tests/AgentCoreTests/VaultChannelBufferTests.swift` `testChangesOverTheBoundWhileASendWaitsBecomeOneManifest` holds the first change batch, gives 5 more change lists with a bound of 3 changes, releases the batch, and asserts that the next request is one manifest and that no other batch goes. Confirm that it fails by its assertions (every list is queued and sent).
- [x] 14.2 GREEN: `VaultChannelSync` gathers the drained changes in one buffer of at most `maximumBufferedChanges` (10 000 by default) and gives the client all of them at once; over the bound it clears the buffer and sends one manifest instead (`NotesChannelClient.resync()`). Verify 14.1 and the full suite.

## 15. The app runs the vaults (workspace OBS-023 tasks 12.23 and 12.24)

- [x] 15.1 RED: `Tests/AgentCoreTests/SessionBoundNotesChannelHTTPTests.swift` asserts that an agent that is not paired sends nothing and that each request uses the paired origin of that moment; `Tests/AgentCoreTests/VaultRuntimeComponentTests.swift` asserts that the runtime component launches one sync per vault, stops the sync of a removed vault, launches a new one, and stops all at the end, and that the registry gives each vault with its resolved folder. Confirm that all fail by their assertions (stubs send and run nothing).
- [x] 15.2 GREEN: `SessionBoundNotesChannelHTTP`, `VaultRuntimeComponent`, `WatchedVaultRegistry.runtimeVaults()`, and `ProductRuntimeFactory` adds the component, which builds a `VaultChannelSync` per vault with FSEvents, the Obsidian CLI rename check and `FileVaultChannelStateStore` at `vault-channels.json` of the support directory. Verify 15.1 and the full suite.
