# Tasks: inbox-watcher-stable-file-detection

Each behaviour below lands as a pair: the first task adds a failing test (file, test name, and assertion named), the second makes it pass. Where a new API would otherwise fail to compile, the failing-test task declares the minimal stub so the observed failure is the behavioural assertion, not a build error. Tooling, documentation, and pure-glue tasks carry their one-line justification for not starting from a failing test.

## 1. Stability decision core (AgentCore)

- [x] 1.1 Add failing test `testQuietFileCrossingFullIntervalIsStable` in `Tests/AgentCoreTests/DownloadStabilityEvaluatorTests.swift`: a fixture sequence writes once at t0, then re-observations with identical size and modification time at t0 + interval report `.stable` carrying evidence naming the quiet duration; anything before the full interval stays `.pending`. Declare `FileSnapshot`, `CandidateStability`, `StabilityEvidence`, and `DownloadStabilityEvaluator` as minimal stubs whose evaluate always returns `.pending` so the failure is behavioural. Confirm it fails.
- [x] 1.2 Implement the evaluator's quiet-interval decision: equal size and modification time observed across the configured interval from first sight yields `.stable(StabilityEvidence)`; less elapsed time yields `.pending`. Verify: `swift test` green for 1.1.
- [x] 1.3 Add failing tests in the same file: `testGrowingFileStaysPending` (size increases between observations past an interval - still pending), `testModificationTimeTouchRestartsClock` (constant size but advancing mtime past an interval - still pending), and `testChangedSnapshotRestartsQuietIntervalFromChange` (after growth stops, stability needs a fresh full interval measured from the last change). Note: all three passed on their first run - task 1.2's baseline-comparison decision already treats any differing snapshot as pending and measures quiet time from the baseline date, which is exactly this behaviour, so no red phase was observable; retained as regression pins for the change-restarts-clock semantics.
- [x] 1.4 Implement change detection: any difference in size or modification time restarts the quiet measurement from the changed observation. No production change required beyond 1.2; verified by running the 1.3 tests (`swift test` green for 1.3).
- [x] 1.5 Add failing test `testDetectedWriterHoldBlocksQueueingDespiteQuietMetadata` in the same file: quiet metadata across the interval with writer-hold detected reports `.pending`; the same sequence with the probe passed reports `.stable`. Confirm the held case fails.
- [x] 1.6 Fold the writer-probe outcome into the decision: stability requires the probe passed where detection applies. Verify: `swift test` green for 1.5.

## 2. Candidate eligibility gates (AgentCore)

- [ ] 2.1 Add failing tests in `Tests/AgentCoreTests/CandidateEligibilityTests.swift`: `testOversizedFileIsRejectedImmediatelyWithLimit` (a snapshot above the ceiling rejects without waiting for stability), `testNonRegularFileIsRejectedNamingReason`, and `testUnreadableFileIsRejectedNamingReason`. Declare `CandidateRejection` and `CandidateEligibilityGate` stubs so failures are behavioural. Confirm they fail.
- [ ] 2.2 Implement the eligibility gate: regular-file-only admission, readability requirement, and the configured size ceiling checked before any stability waiting, each rejection carrying its reason. Verify: `swift test` green for 2.1.

## 3. Temporary-suffix exclusion (AgentCore)

- [x] 3.1 Add failing tests in `Tests/AgentCoreTests/PartialDownloadHeuristicsTests.swift`: `testKnownTemporarySuffixesAreRecognized` (.download, .crdownload, .part, .partial, case-insensitive), `testCleanNamesAreNotFlagged`, and in `DownloadStabilityTrackerTests` `testSuffixedPathIsNeverQueuedDespiteFullQuietEvidence`. Confirm they fail.
- [x] 3.2 Implement `PartialDownloadHeuristics` over the documented suffix list and make tracker assessment refuse suffixed paths regardless of evidence. Verify: `swift test` green for 3.1.

## 4. Per-path quiet-period tracking (AgentCore)

- [x] 4.1 Add failing tests in `Tests/AgentCoreTests/DownloadStabilityTrackerTests.swift` driving real temporary-directory files through `FileManagerMetadataProvider` with an injected virtual clock: `testFirstObservationOfFreshPathIsPending`, `testStablePathEmitsExactlyOneStableOutcomeOnRepeatedAssessments`, `testVanishedPathResetsTrackingSoReappearanceStartsFresh`, and `testRenamedInFileWaitsFullIntervalFromFirstSight` (mtime predating discovery must not shortcut). Declare the provider protocol, tracker, and metadata-backed implementation as stubs so failures are behavioural. Confirmed: five of six failed on their stability/rejection assertions (`testFirstObservationOfFreshPathIsPending` passed trivially against the never-stable stub and is retained as the fresh-path pin).
- [x] 4.2 Implement `QuietPeriodTracker` keyed by path over the evaluator and gates, plus the FileManager-backed snapshot provider and the advisory writer-hold probe (open for writing without create/truncate; refusal counts as held). Verify: `swift test` green for 4.1 (`Executed 6 tests, with 0 failures`).

## 5. Debounced scheduling seam (AgentCore)

- [x] 5.1 Add failing tests in `Tests/AgentCoreTests/DebouncerTests.swift` with a manual scheduler: `testBurstInsideWindowFiresOnceAtWindowEnd` (several triggers, one firing scheduled from the last trigger) and `testTriggerAfterWindowClosesSchedulesAnotherFire`. Declare `WatchScheduling` and `Debouncer` stubs so failures are behavioural. Confirm they fail.
- [x] 5.2 Implement `Debouncer` over the scheduler seam and the dispatch-queue-backed scheduler production implementation. Verify: `swift test` green for 5.1 (`Executed 10 tests, with 0 failures` across groups 3-5).

## 6. Inbox watch coordination (AgentCore)

- [x] 6.1 Add failing tests in `Tests/AgentCoreTests/InboxWatchCoordinatorTests.swift` using scripted folder monitors, the manual scheduler, real temporary directories, and injected clocks: `testStartScansPreExistingFilesAndEmitsCandidateAfterQuietPeriod` (regular file present at start becomes exactly one stable candidate after one quiet interval), and `testDisabledFolderIsNeverObserved`. Declare `InboxFolderMonitoring`, `WatchedFolderTarget`, folder status/degradation types, and the coordinator actor as empty shells so failures are behavioural. Confirmed: both failed against the no-op shell.
- [x] 6.2 Implement coordinator start: resolve enabled folders, run the initial directory scan, observe new regular files through the tracker, schedule reassessments via the debouncer, and deliver stable candidates to the consumer callback exactly once per path. Verify: `swift test` green for 6.1.
- [x] 6.3 Add failing tests: `testUnavailableFolderAtStartDegradesAloneWhileOtherStillYieldsCandidates`, `testFolderDeletedMidWatchDegradesWithoutStoppingOthers`, and `testDegradedFolderStopsProducingCandidates`. Confirmed: they failed against the partial implementation; the stops-producing assertions live inside the mid-watch test's second phase.
- [x] 6.4 Implement degradation isolation: missing/unreadable folder during scan or start marks only that folder degraded with its reason and drops its monitor. Verify: `swift test` green for 6.3.
- [x] 6.5 Add failing tests: `testDuplicateNotificationsKeepSingleCandidateOutcome` (scripted repeated events for one path produce one candidate), `testStopEndsEmissionsAndIsIdempotent` (post-stop scripted events emit nothing; second stop is safe). Note: the stop test passed on its first run - the shell already had no emissions to stop, so there was no red phase to observe; retained as the teardown pin.
- [x] 6.6 Implement event idempotence through the path-keyed completion cache and clean stop semantics. Verify: `swift test` green for 6.5 (`Executed 7 tests, with 0 failures` across the coordinator suites).

## 7. FSEvents folder monitor (AgentCore)

- [x] 7.1 Add failing test `testCreatedFileDeliversEventWithinWindow` in `Tests/AgentCoreTests/FSEventsFolderMonitorTests.swift`: a monitor started on a real temporary directory delivers at least one event callback after a file is created, within a generous expectation window. Declare the monitor type as a shell whose callbacks never fire so the failure is the timeout-free behavioural assertion. Confirmed: the expectation timed out against the shell.
- [x] 7.2 Implement the FSEvents wrapper: stream creation with file-level events over the resolved path, delivery onto its serial queue, start, stop, and invalidate hygiene. Verify: `swift test` green for 7.1 (event delivered well inside the window).
- [x] 7.3 Add failing tests in the same file: `testStartOnMissingDirectoryFailsClosedWithoutCrashing` and `testStopIsSafeToRepeat` - deterministic lifecycle assertions needing no event timing. Confirmed: the missing-directory test failed (no throw); the stop-repeat test passed on its first run because the no-op shell was already harmless, so it is retained as the idempotence pin.
- [x] 7.4 Make start validate the path and surface failure instead of creating a dead stream, and make repeated stop/invalidate harmless. Verify: `swift test` green for 7.3 (`Executed 3 tests, with 0 failures`).

## 8. Documentation and full gate

- [x] 8.1 Update the README status block: inbox watching with completed/stable-file detection exists; hashing/journal/upload remain future work. Documentation change, no failing test applies. Verify: status block matches this change's scope with no overclaim.
- [x] 8.2 Run the complete gate: `swift build`, `swift test`, `swift build -c release`, `.build/release/RatatoskrExportAgent --smoke`, `swiftlint`, `openspec validate --all --strict`, and `openspec validate --archived`, all green. This is the cross-cutting verification task spanning all groups above. Observed: 75 tests / 0 failures, smoke exit 0, 0 lint violations across 51 files after two ceiling refactors (coordinator type body split into the scanning extension; monitor stream creation extracted), 5+1 validation items passed.

## 9. Ship

- [ ] 9.1 Commit the work on `feat/inbox-watcher-stable-file-detector` as conventional commits grouped by concern (stability core, eligibility gates, suffix exclusion, tracker, debounce, coordination, FSEvents monitor, docs/gate). Verify: `git log` shows the grouped history and the worktree diff is fully committed.
- [ ] 9.2 Merge into `main`, push `origin main`, then remove the worktree and delete the feature branch. Verify: remote `main` contains the merge commit; `git worktree list` and the branch list no longer contain this task's entries.
