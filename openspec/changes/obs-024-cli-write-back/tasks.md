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

- [x] 8.1 RED: `ObsidianCliApplyLocalTests` `testBaseMismatchChangesNothingAndSendsTheLocalFile` and `testUpdateWritesTheBytesAtomicallyAfterABaseMatch`, and `Tests/AgentCoreTests/ObsidianCliPropertyTests.swift` `testSetPassesTheValueAndItsType`, `testRemovePassesTheName` and `testSetPropertyContentIsCheckedAgainstItsDigest`. Confirm that the digest test fails by its assertions (the CLI runs with content whose hash is not the digest); the other four pin behaviour that exists, each with a mutation that makes it fail.
- [x] 8.2 GREEN: the content of `set_property` goes through the digest check. Verify 8.1 and the full suite.

## 9. An unfinished create and the content bound (workspace OBS-024 tasks 12.13 and 12.14)

- [x] 9.1 RED: `ObsidianCliApplyLocalTests` `testAnEmptyFileOfAnUnfinishedCreateIsFinished` (a create with no base finds an empty file at its path; the agent writes the bytes without `obsidian create` and reports applied) and `testContentLongerThanItsLengthIsRefused` (`failed` with `notes.channel.refused`, nothing written), and `Tests/AgentCoreTests/NotesChannelHTTPTests.swift` `testABoundedBodyIsReadUpToItsBoundAndOneByte`. Confirm that all fail by their assertions.
- [x] 9.2 GREEN: a create with no base whose file is empty finishes the write; the content read sends `length_bytes` as the bound of the body, the HTTPS binding reads at most the bound and one byte, and content longer than `length_bytes` is refused. Verify 9.1 and the full suite.

## 10. Gate

- [x] 10.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 11. A rename with its link rewrites is one group (workspace OBS-024 tasks 12.15 and 12.16)

- [x] 11.1 RED: `Tests/AgentCoreTests/ObsidianCliRewriteTests.swift` `testRenameReportsTheHashOfEachLinkingNote` (the result lists `rewrites` with `applied` and the hash of each linking note after the CLI; only the note whose hash is not its `expected_sha256` is uploaded, before the result), `testARewriteBaseMismatchRefusesTheGroupBeforeTheCLI` (top-level `base_mismatch`, no CLI command, the renamed file stays, the linking note goes to the change buffer) and `testAnUnsafeRewritePathFailsTheGroup` (`failed` `notes.write.unsafe_path`, no CLI command). Confirm that all fail by their assertions.
- [x] 11.2 GREEN: decode `rewrites` of a queued rename or move; check the path and the base of each linking note before the CLI; after the CLI, hash each linking note (once more after `settle` when a note still has its base hash), upload each hash that is not its `expected_sha256`, and send `rewrites` in the `applied` result. Verify 11.1 and the full suite. The agent has no plain-move path: a rename or a move always runs the Obsidian CLI, so `notes.write.unsupported` has no case to cover.

## 12. Gate

- [x] 12.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 13. A group refusal names each linking note, and a result is sent again (workspace OBS-024 tasks 12.17 and 12.18)

- [x] 13.1 RED: `ObsidianCliRewriteTests.testARewriteBaseMismatchRefusesTheGroupBeforeTheCLI` expects `{"outcome":"base_mismatch","local_sha256":<hash of the renamed file>,"rewrites":[…]}` with every listed linking note as `base_mismatch` with its own hash (null for a note that is gone) and no `applied` entry, and the notes that differ in the change buffer; `Tests/AgentCoreTests/ObsidianCliResendTests.swift` `testAResultIsSentAgainAfterAServerError` (after a `503` on the result of a `set_property`, the next pass sends the same `applied` result and does not set the property again) and `testAResultIsSentAgainAfterANetworkError` (a rename whose result met a network error is reported `applied` on the next pass, renamed once). Confirm that the first two fail by their assertions; the third pins behaviour that exists, with a mutation that makes it fail.
- [x] 13.2 GREEN: a linking note that differs refuses the group with the hash of the renamed file and a `base_mismatch` entry with its own hash for every listed note; the client keeps each result that did not get `200` (or `404` `notes.device_operation.not_found`) by operation id and sends it again on the next pass in place of a new apply, and forgets the results of operations that a full pass no longer lists. Verify 13.1 and the full suite.
- [x] 13.3 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 14. Group refusal of the renamed file, kept results across a restart, and dropped results (workspace OBS-024 tasks 12.19 and 12.20)

- [x] 14.1 RED: `ObsidianCliRewriteTests.testAFileMismatchWithRewritesNamesEveryLinkingNote` (the renamed file has a newer edit: `base_mismatch` with its hash and every linking note with its own hash), and `Tests/AgentCoreTests/ObsidianCliRestartTests.swift` `testAKeptResultSurvivesARestart` (a result kept in `FileDeviceResultStore` is sent by a new client, and the property is set once), `testAMovedFileWithItsExpectedHashIsAlreadyApplied` (a moved file with the `expected_sha256` of the rename is already applied) and `testAKeptResultThatNotesRefusesIsDroppedAndAppliedAgain` (after a `400` on a kept result, the next pass applies again). Confirm that all fail by their assertions (a stub store keeps nothing).
- [x] 14.2 GREEN: a base mismatch of the renamed file in a group gives the group refusal with every linking note; `FileDeviceResultStore` keeps the unsent results in `device-results.json` of the support directory, and the client loads them before its first pass and saves each change; `alreadyApplied` takes a moved file with the expected hash or the base hash; a kept result that gets a `4xx` other than `409` (and other than `404` `notes.device_operation.not_found`), or whose upload finds stale bytes, is dropped, and the next pass applies again. Verify 14.1 and the full suite.
- [x] 14.3 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 15. The result file is the owner's, and kept results survive errors (workspace OBS-024 tasks 12.21 and 12.22)

- [x] 15.1 RED: `Tests/AgentCoreTests/DeviceResultStoreTests.swift` `testTheFileIsReadableByTheOwnerOnly` (the file is `0600`, the support directory `0700`, no temporary file is left) and `testACorruptFileIsMovedAsideAndTheStoreStartsEmpty` (the file moves to `device-results.json.corrupt-<seconds>` with one log line, and the store works again); `ObsidianCliRestartTests` `testAKeptResultStaysOnARetryableRefusal` (`429` keeps the result), `testAKeptResultIsDroppedOnAConflictThatIsNotBytesMissing` (a `409` with another code drops it) and `testAFailedLoadIsTriedAgainOnTheNextPass` (an unreadable file is loaded again on the next pass). Confirm that all fail by their assertions (stub `now` and `log` parameters of the store).
- [x] 15.2 GREEN: write `device-results.json` through a temporary file created `0600` and renamed, and set the support directory to `0700`; move a corrupt file aside and log one line; let a read error other than a missing file throw, so the client keeps its results and loads again on the next pass, and set `resultsLoaded` only after a load; keep a result on `401`, `403`, `408`, `429` or a retryable fault, and drop it on any other `4xx` (also a `409` that is not `notes.channel.bytes_missing`). Verify 15.1 and the full suite.
- [x] 15.3 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.

## 16. A move into a missing folder (real CLI acceptance follow-up)

- [x] 16.1 RED: add `ObsidianCliMoveParentTests.testMoveCreatesTheMissingDestinationFolderBeforeTheCLI`. The fake CLI only renames the file, as real Obsidian 1.14.4 does; it does not create the folder. The test ran before the implementation: one test failed because the result was `export_agent.write.obsidian_failed`, the target was absent and the source stayed. Log `/tmp/ratatoskr-obsidian-move-red.log`.
- [x] 16.2 GREEN: after the path, base and existing-target checks, create the destination folder, then run the unchanged Obsidian move command. The new test passes. A standalone acceptance harness linked the production `NotesChannelClient`, `ObsidianCLIApply` and `ProcessObsidianCLIRunner` to the real signed Obsidian installer and engine 1.14.4 in an isolated synthetic vault. The nested move completed, preserved bytes and reported the correct hash; only its Notes HTTP queue/result peer was synthetic. Log `/tmp/ratatoskr-real-obsidian-cli-acceptance.log`.
- [x] 16.3 Run every DEVELOPMENT gate, fleet checks, OpenSpec validation and independent review. All six DEVELOPMENT commands and eight fleet steps passed. The full suite ran 307 tests: 306 passed, one existing opt-in Keychain test was skipped, zero failed. SwiftLint reported 16 existing warnings and no serious violation; offline Zizmor found no issue. The CI-pinned OpenSpec 1.10.0 validated all 26 active items and all nine archived changes. Independent review found no actionable P0 defect. No failing test first: validation record.
