## 1. The `cli` channel applies queued writes (workspace OBS-024 tasks 12.1 and 12.2)

- [x] 1.1 RED: add `Tests/AgentCoreTests/ObsidianCliApplyTests.swift` with `testRenameUsesObsidianRename`, `testDeleteNeverPermanent` and `testClosedObsidianLeavesQueue`, against a fake `obsidian` executable that records its arguments, and `Tests/AgentCoreTests/NotesChannelHTTPTests.swift` `testQueryOfThePathIsSentAsAQuery`. Confirm that all fail by their assertions (stubs apply nothing and report a pass that answered nothing, and the binding encodes `?` into the path).
- [x] 1.2 GREEN: implement the queue reader and the CLI apply step, keep the query of a path in the HTTPS binding, and read the queue from each vault sync. Verify 1.1 and the full suite, and document the requirement of Obsidian 1.12.7 or later in `README.md`.

## 2. Gate

- [x] 2.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 3. Unsafe paths, the hash after `property:set`, the CLI thread, and pins (workspace OBS-024 tasks 12.3 and 12.4)

- [x] 3.1 RED: add `Tests/AgentCoreTests/ObsidianCliApplyPathTests.swift` (`testUnsafePathsFailWithUnsafePath`, `testMoveUsesObsidianMoveWithTheTargetPath`, `testCreateMakesAnEmptyFileWithTheCLIThenWritesTheBytes`) and `Tests/AgentCoreTests/ObsidianCliApplyResultTests.swift` (`testBytesMissingUploadsTheFileAndSendsTheResultAgain`, `testAPassAfterACrashBeforeTheResultReportsApplied`, `testSetPropertyReadsTheHashAgainWhenTheFileDidNotChangeYet`, `testTheCLIRunsOnItsOwnThread`), with the shared fixture `Tests/AgentCoreTests/ObsidianCliTestCase.swift`. Confirm that the unsafe-path test fails because the code is `export_agent.write.path_outside_vault`, the `property:set` test because the hash is read once before the file changed, and the thread test because the CLI runs on a thread of the pool (a stub `settle` parameter is never called). The other 4 tests pin behaviour that exists; for each, record a mutation that makes it fail.
- [x] 3.2 GREEN: report a refused path as `failed` with `notes.write.unsafe_path`; after `property:set` or `property:remove`, when the file still has the base hash, wait once (`settle`, 0.5 s by default) and read the hash again; run each CLI command on a dedicated thread named `obsidian-cli`. Verify 3.1 and the full suite.

## 4. The menu shows a vault that waits for Obsidian (workspace OBS-024 tasks 12.5 and 12.6)

- [x] 4.1 RED: `Tests/AgentCoreTests/VaultStatusMenuProjectionTests.swift` `testAVaultThatWaitsForObsidianHasItsTitle` asserts the title `Vault Work: waits for Obsidian`, and `Tests/AgentCoreTests/VaultSyncObsidianStatusTests.swift` `testAPassThatWaitsForObsidianShowsInTheStatus` asserts that a sync whose queue holds an operation while the app does not run has the status `awaitingObsidian`, and `connected` after a pass while the app runs. Confirm that both fail by their assertions (a stub status case that the sync never gives, with the title of `connected`).
- [ ] 4.2 GREEN: the sync keeps the end of the last queue pass, `status()` gives `awaitingObsidian` after a pass that waits for Obsidian unless the channel is stopped or retrying, and the menu shows `Vault <name>: waits for Obsidian`. Verify 4.1 and the full suite.

## 5. Gate

- [ ] 5.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.
