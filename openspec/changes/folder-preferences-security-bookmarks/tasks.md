# Tasks: folder-preferences-security-bookmarks

Each behaviour below lands as a pair: the first task adds a failing test (file, test name, and assertion named), the second makes it pass. Where a new API would otherwise fail to compile, the failing-test task declares the minimal stub so the observed failure is the behavioural assertion, not a build error. Tooling, documentation, and pure-glue tasks carry their one-line justification for not starting from a failing test.

## 1. Configuration contract break

- [x] 1.1 Add failing test `testWatchedFoldersFieldIsRejectedAsUnknown` in `Tests/AgentCoreTests/ConfigurationLoadingTests.swift`: decoding a schema-version-1 document that contains `watchedFolders` throws, and the error description names `watchedFolders`. Confirm it fails because the field is still accepted today.
- [x] 1.2 **BREAKING** (permitted while development status holds): delete `watchedFolders` from `AgentConfiguration`, its decoder, its documented defaults, and the `emptyWatchedFolderEntry` rejection; update the scaffold-era tests that reference the field (`testMissingFileYieldsDefaults` assertions drop the watched-folder expectations; `testEmptyWatchedFolderEntryFails` is removed with its behaviour). Verify: `swift test` green for 1.1.

## 2. Preferences document persistence (AgentCore)

- [x] 2.1 Add failing tests `testMissingFileYieldsEmptyRegistry` and `testSavedEntriesSurviveReload` in `Tests/AgentCoreTests/FolderPreferencesDocumentTests.swift`: loading a nonexistent file yields an empty registry; saving one entry (stable ID, display path, non-empty bookmark data) and reloading restores it identically with enabled-on and `archiveAfterUpload` defaults. Declare the load/save entry points as stubs so the failures are behavioural. Confirm both fail.
- [x] 2.2 Implement the preferences document: folder-entry value type (UUID identity, sanitized display path, enabled flag, two-case archive-policy enum defaulting to `archiveAfterUpload`, bookmark data), missing-file default of an empty registry, atomic save, and reload fidelity. Verify: `swift test` green for 2.1.
- [x] 2.3 Add failing tests `testUnsupportedSchemaVersionFails`, `testUnknownFieldIsRejectedAndNamed`, `testDuplicateFolderIDFailsNamingTheID`, `testEmptyBookmarkDataFailsNamingTheEntry`, and `testValidationErrorNamesFileAndReasonWithoutContents` in the same file. Confirm they fail.
- [x] 2.4 Implement strict decoding mirroring typed-configuration conventions: version gate first, key-set comparison against known fields, duplicate-ID and empty-bookmark-data rejection naming the offender, and a typed error carrying the file location plus reason without raw contents. Verify: `swift test` green for 2.3.
- [x] 2.5 Add failing tests `testDisabledFlagSurvivesReload` and `testPreserveInPlacePolicySurvivesReload` in the same file: toggling enabled off and switching policy to preserve-in-place each survive a save/reload cycle. Note: both passed on their first run - task 2.2's generic Codable entry already persists every field, so there was no red phase to observe; they are retained as regression pins for non-default values.
- [x] 2.6 Persist the enabled flag and archive policy through encode/decode. No production change required beyond 2.2's codec; verified by running the 2.5 tests (`swift test` green for 2.5 and the whole AgentCore suite).

## 3. Security-scoped bookmark lifecycle (AgentCore)

- [x] 3.1 Add failing test `testBookmarkRoundTripResolvesSameDirectory` in `Tests/AgentCoreTests/FolderBookmarkStoreTests.swift`: creating a security-scoped bookmark for a temporary directory through the real FileManager-backed store, then resolving it, yields a URL to that same directory whose contents are readable. Declare the bookmark-store protocol plus a throwing stub so the failure is behavioural. Confirm it fails.
- [x] 3.2 Implement the FileManager-backed store: `.withSecurityScope` creation, `.withSecurityScope` resolution reporting the stale flag, and start/stop scoped-access wrappers. Verify: `swift test` green for 3.1; observed headless evidence recorded here - creation and resolution succeed unsandboxed in the plain macOS test process (`Executed 1 test, with 0 failures`), so the round trip is exercised directly in CI without instrumented fallback.
- [x] 3.3 Add failing test `testFreshInstanceResolvesStoredBytes` in the same file: bookmark bytes produced by one store instance resolve under a newly constructed instance given only the serialized data. Note: passed on its first run - task 3.2 implemented resolution stateless from the start, so no red phase was observable; retained as the regression pin for restart robustness.
- [x] 3.4 Ensure resolution depends solely on bookmark bytes with no hidden instance state, so persisted bookmarks survive process restarts. No further production change required beyond 3.2; verified by running the 3.3 test (`swift test` green).
- [x] 3.5 Add failing tests `testCorruptBytesMapToNeedsReauthorization`, `testStaleBookmarkMapsToNeedsReauthorization`, `testVanishedTargetMapsToMissing`, and `testPermissionFailureMapsToDenied` in `Tests/AgentCoreTests/FolderAccessStateTests.swift`, against the pure classifier declared as a stub. Confirm all four fail.
- [x] 3.6 Implement the pure access-state classifier: unparseable/unresolvable bytes and stale-but-existing targets map to needs-reauthorization, resolvable-but-vanished targets map to missing, permission-coded probe failures map to denied. Verify: `swift test` green for 3.5 (`Executed 37 tests, with 0 failures` across the suite).
- [x] 3.7 Add failing test `testReleaseDropsHeldAccess` in `FolderBookmarkStoreTests.swift`: after resolving and releasing a folder, the store reports no active access for it. Note: passed on its first run - the unsandboxed test process receives scoped-access grants, so task 3.2's tracking already satisfied both assertions; retained as the regression pin for release hygiene.
- [x] 3.8 Track active scoped-access handles and drop them on release. No further production change required beyond 3.2; verified by running the 3.7 test plus the suite (`swift test` green), followed by a behaviour-preserving cleanup of `startAccessing` with the suite re-run green.

## 4. Watched-folder registry (AgentCore)

- [x] 4.1 Add failing tests in `Tests/AgentCoreTests/WatchedFolderRegistryTests.swift` with injected recording stubs: `testAddCreatesPersistedEntryWithCreatedBookmark` (entry saved before add returns, bookmark bytes come from the store), `testAddingSameFolderTwiceYieldsOneEntry`, `testRemoveDropsEntryAndReleasesAccess`, and `testUnresolvableFolderStaysListedAsNeedsReauthorization`. Confirm they fail.
- [x] 4.2 Implement the registry orchestrating document and bookmark store: add with path-based duplicate collapse, removal releasing held access, and per-entry access-state queries. Verify: `swift test` green for 4.1.
- [x] 4.3 Add failing test `testFailedSaveLeavesRegistryUnchanged` in the same file: with a store whose save throws, add throws and the in-memory registry still excludes the folder. Confirm it fails.
- [x] 4.4 Make add transactional - persist first, commit in-memory only on success, propagate failure. Verify: `swift test` green for 4.3 (`Executed 42 tests, with 0 failures` across the suite).

## 5. Menu-bar settings surface (RatatoskrExportAgent)

- [x] 5.1 Add failing test `testStatusItemMenuOffersSettingsAndQuit` in `Tests/RatatoskrExportAgentTests/StatusItemMenuTests.swift`: after the bootstrap presentation installs, the status item carries a menu containing items titled "Settings…" and "Quit Ratatoskr". Declare the menu-building helper as a stub so the failure is behavioural. Confirm it fails.
- [x] 5.2 Extend the bootstrap presentation to attach that menu; wire Quit to application termination and Settings to presenting the settings window. Verify: `swift test` green for 5.1; Settings presentation completed with task 5.5 and regression-checked by 5.6.
- [x] 5.3 Add failing tests in `Tests/RatatoskrExportAgentTests/FolderSettingsViewModelTests.swift` over a view model backed by injected stubs: `testRowsMirrorRegistryEntries` (one row per entry carrying display path, enabled, policy, access state), `testToggleDisablesEntryAndPersists`, and `testPolicyChangePersists`. Confirm they fail.
- [x] 5.4 Implement `FolderSettingsViewModel` over the registry exposing rows, toggle, policy change, and remove-request handling. Verify: `swift test` green for 5.3.
- [x] 5.5 Build the SwiftUI folder-settings view, the window controller hosting it, the remove-confirmation alert, and the NSOpenPanel picker adapter. Cannot start from a failing test: pure AppKit/SwiftUI glue whose behaviour is already pinned by the view-model and menu tests. Verify: `swift build` passes and the existing `LaunchBehaviorTests` smoke tests stay green.
- [x] 5.6 Run the full existing shell suite to confirm the menu/window addition did not perturb accessory presentation or smoke mode (no new test; regression check on `LaunchBehaviorTests`). Verify: `swift test` green including smoke launch tests (`Executed 46 tests, with 0 failures`).

## 6. Documentation and full gate

- [x] 6.1 Update the README status block: watched-folder preferences with security-scoped bookmarks and the settings window exist; inbox watching itself remains future work. Documentation change, no failing test applies. Verify: the status block matches the proposal scope with no overclaim.
- [x] 6.2 Run the complete gate: `swift build`, `swift test`, `swift build -c release`, `.build/release/RatatoskrExportAgent --smoke`, `swiftlint`, `openspec validate --all --strict`, and `openspec validate --archived`, all green. This is the cross-cutting verification task spanning all groups above. Observed: 46 tests / 0 failures, smoke exit 0, 0 lint violations, 4+1 validation items passed.

## 7. Ship

- [x] 7.1 Commit the work on `feat/folder-preferences-security-bookmarks` as conventional commits grouped by concern (configuration break, preferences document, bookmark lifecycle, registry, settings surface, docs/gate). Verify: `git log` shows the grouped history and the worktree diff is fully committed.
- [ ] 7.2 Merge into `main`, push `origin main`, then remove the worktree and delete the feature branch. Verify: remote `main` contains the merge commit; `git worktree list` and the branch list no longer contain this task's entries.
