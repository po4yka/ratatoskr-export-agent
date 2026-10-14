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
