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
- [x] 4.2 GREEN: the sync keeps the end of the last queue pass, `status()` gives `awaitingObsidian` after a pass that waits for Obsidian unless the channel is stopped or retrying, and the menu shows `Vault <name>: waits for Obsidian`. Verify 4.1 and the full suite.

## 5. Gate

- [x] 5.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 6. More unsafe paths (workspace OBS-024 tasks 12.7 and 12.8)

- [x] 6.1 RED: `Tests/AgentCoreTests/ObsidianCliApplyPathTests.swift` `testBackslashesControlCharactersColonsAndTrailingDotsFailWithUnsafePath` queues updates of `A\.obsidian\plugins\x.md`, `..\x.md`, `A\u{0}.md`, `A\nB.md`, `A\u{7F}.md`, `Notes/.. /x.md`, `Notes/. /x.md`, `A:B.md`, `Notes./x.md` and `Notes /x.md`, and moves of `Notes/A.md` to `Notes\B.md` and `Notes/B:C.md`. It asserts that each is `failed` with `notes.write.unsafe_path`, that only `obsidian version` runs, that no content is read and that nothing is written. Confirm that it fails by its assertions. The search for the nearest existing folder stops at `/`, because a path with NUL never exists and the search did not end.
- [x] 6.2 GREEN: refuse a path or a target path that holds `\`, `:`, a C0 control character or DEL, a segment that ends in `.` or a space, or a first segment `.obsidian` in any case, before any read or CLI run. Verify 6.1 and the full suite.

## 7. A local error settles the operation (workspace OBS-024 tasks 12.9 and 12.10)

- [x] 7.1 RED: `Tests/AgentCoreTests/ObsidianCliApplyLocalTests.swift` `testALocalErrorFailsTheOperationAndThePassGoesOn` queues an update of `Folder.md`, which is a folder, and then an update of `A.md`. It asserts that the first result is `failed` with `notes.channel.refused` and that the second is applied in the same pass. Confirm that it fails by its assertions (the error ends the pass).
- [x] 7.2 GREEN: an error of the apply step that is not an error of the content read gives `failed` with `notes.channel.refused`; an error of the content read (the transport) still ends the pass. A file that is not a regular file has no hash. Verify 7.1 and the full suite.

## 8. Base mismatch, update and `set_property` (workspace OBS-024 tasks 12.11 and 12.12)

- [ ] 8.1 RED: `ObsidianCliApplyLocalTests` `testBaseMismatchChangesNothingAndSendsTheLocalFile` and `testUpdateWritesTheBytesAtomicallyAfterABaseMatch`, and `Tests/AgentCoreTests/ObsidianCliPropertyTests.swift` `testSetPassesTheValueAndItsType`, `testRemovePassesTheName` and `testSetPropertyContentIsCheckedAgainstItsDigest`. Confirm that the digest test fails by its assertions (the CLI runs with content whose hash is not the digest); the other four pin behaviour that exists, each with a mutation that makes it fail.
- [ ] 8.2 GREEN: the content of `set_property` goes through the digest check. Verify 8.1 and the full suite.

## 9. An unfinished create and the content bound (workspace OBS-024 tasks 12.13 and 12.14)

- [ ] 9.1 RED: `ObsidianCliApplyLocalTests` `testAnEmptyFileOfAnUnfinishedCreateIsFinished` (a create with no base finds an empty file at its path; the agent writes the bytes without `obsidian create` and reports applied) and `testContentLongerThanItsLengthIsRefused` (`failed` with `notes.channel.refused`, nothing written), and `Tests/AgentCoreTests/NotesChannelHTTPTests.swift` `testABoundedBodyIsReadUpToItsBoundAndOneByte`. Confirm that all fail by their assertions.
- [ ] 9.2 GREEN: a create with no base whose file is empty finishes the write; the content read sends `length_bytes` as the bound of the body, the HTTPS binding reads at most the bound and one byte, and content longer than `length_bytes` is refused. Verify 9.1 and the full suite.

## 10. Gate

- [ ] 10.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.
