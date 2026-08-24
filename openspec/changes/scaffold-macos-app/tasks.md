# Tasks: scaffold-macos-app

Each behaviour below lands as a pair: the first task adds a failing test (file, test name, and assertion named), the second makes it pass. Where a new API would otherwise fail to compile, the failing-test task declares the minimal stub so the observed failure is the behavioural assertion, not a build error. Tooling, documentation, and generated-file tasks carry their one-line justification for not starting from a failing test.

## 1. Package scaffold

- [x] 1.1 Create `Package.swift` declaring products and targets `AgentCore`, `AgentLog` (libraries) and `RatatoskrExportAgent` (executable), plus test targets `AgentCoreTests` and `AgentLogTests`, with compiling stub sources in each target. Cannot start from a failing test: the package manifest is configuration that must exist before any test can execute. Verify: `swift build` and `swift test` succeed with zero tests.

## 2. Typed configuration (AgentCore)

- [x] 2.1 Add failing test `testMissingFileYieldsDefaults` in `Tests/AgentCoreTests/ConfigurationLoadingTests.swift`: loading a nonexistent file path returns the default configuration — `backendBaseURL` nil, `watchedFolders` empty, `maxArchiveBytes` equal to 2 GiB, `maxConcurrentUploads` equal to 2. Declare the loading entry point as a stub so the failure is the assertion. Confirm the test fails because defaults are not produced.
- [x] 2.2 Implement the configuration value type and `load` entry point returning documented defaults when the file does not exist. Verify: `swift test` green for 2.1.
- [x] 2.3 Add failing tests `testUnsupportedSchemaVersionFails` and `testMissingSchemaVersionFails` in the same file: decoding a document whose `schemaVersion` is not 1, or which omits it, throws an error stating only schema version 1 is supported. Confirm both fail.
- [x] 2.4 Decode and check `schemaVersion` equals 1 before anything else; abort with the version error otherwise, with no compatibility mapping. Verify: `swift test` green for 2.3.
- [x] 2.5 Add failing test `testUnknownFieldIsRejectedAndNamed`: a document containing a key outside the schema-version-1 set fails decoding and the error names the offending field. Confirm it fails.
- [x] 2.6 Compare the keyed container's keys against the known schema keys after the version gate and abort naming any extra key. Verify: `swift test` green for 2.5.
- [x] 2.7 Add failing tests `testHttpsEndpointAccepted`, `testPlainHttpToPublicHostRejected` (error identifies the insecure endpoint), and `testPlainHttpLoopbackAccepted` parameterized over exactly `localhost`, `127.0.0.1`, `::1`. Confirm they fail.
- [x] 2.8 Implement backend URL validation: https always allowed; plain http allowed only when the host is in the loopback set. Verify: `swift test` green for 2.7.
- [x] 2.9 Add failing tests `testNonPositiveMaxArchiveBytesRejected` and `testZeroMaxConcurrentUploadsRejected`: zero/negative byte budget fails naming `maxArchiveBytes`; concurrency below one fails naming `maxConcurrentUploads`. Confirm they fail.
- [x] 2.10 Enforce positive budget validation with errors naming the offending field. Verify: `swift test` green for 2.9.
- [x] 2.11 Add failing test `testEmptyWatchedFolderEntryFails`: an empty string inside `watchedFolders` fails loading and reports the offending entry. Confirm it fails.
- [x] 2.12 Reject empty watched-folder entries. Verify: `swift test` green for 2.11.
- [x] 2.13 Add failing test `testValidationErrorNamesFileAndReasonWithoutContents`: for a validation failure, the error description contains the configuration file path and the reason and contains none of the file's raw contents. Confirm it fails.
- [x] 2.14 Introduce the typed error carrying file location plus reason and ensure no description embeds raw file contents. Verify: `swift test` green for 2.13 and the whole AgentCore suite.

## 3. Privacy logging (AgentLog)

- [x] 3.1 Add failing tests in `Tests/AgentLogTests/LogRedactorTests.swift`: `testAbsolutePathReplacedWithPlaceholder` (final filename component no longer present), `testHomeRelativePathRedacted`, `testBareFilenameWithExtensionRedacted`, and `testMessageWithoutPathsPassesThroughUnchanged`. Declare the redactor as a stub so failures are behavioural. Confirm all four fail.
- [x] 3.2 Implement the pure `LogRedactor` with narrow anchored patterns for absolute POSIX paths, home-relative paths, and bare filenames carrying an extension, each replaced by the fixed `<path>` placeholder. Verify: `swift test` green for 3.1.
- [x] 3.3 Add failing tests in `Tests/AgentLogTests/AgentLoggerTests.swift` against the injectable log sink: `testDebugLevelIsRedactedLikeAnyLevel`, `testVerboseToggleRevealsPathVerbatim`, `testDefaultKeepsPlaceholder`. Confirm they fail.
- [x] 3.4 Implement the logging facade that routes formatted messages through the redactor according to the Boolean injected at construction. Verify: `swift test` green for 3.3 and the whole AgentLog suite.

## 4. Application shell (RatatoskrExportAgent)

- [x] 4.1 Add failing test `testAccessoryPresentationIsApplied` in `Tests/RatatoskrExportAgentTests/LaunchBehaviorTests.swift`: invoking the bootstrap presentation helper leaves `NSApplication.shared.activationPolicy()` equal to `.accessory`. Stub the helper minimally so the failure is the assertion. Confirm it fails.
- [x] 4.2 Implement the bootstrap presentation helper: accessory activation policy and installation of the single status-bar item, no window. Verify: `swift test` green for 4.1.
- [x] 4.3 Add failing test `testSmokeLaunchExitsZeroWithinBound`: spawning the built binary with `--smoke` terminates with exit code 0 within the bounded interval. Confirm it fails (the current stub never performs the bounded successful exit).
- [x] 4.4 Implement `main` argument handling and the smoke path: run the identical startup sequence — presentation helper invoked, status item confirmed installed — then schedule the watchdog that exits 0 shortly after reaching the running state. Verify: `swift test` green for 4.3.
- [x] 4.5 Add failing test `testUnknownArgumentPrintsUsageAndExitsNonZero`: spawning the binary with an undefined flag exits non-zero and writes usage text to standard error. Confirm it fails.
- [x] 4.6 Reject unrecognized arguments with usage on stderr and a non-zero exit; accepted arguments remain only `--smoke` and none. Verify: `swift test` green for 4.5 and the full suite.

## 5. SwiftLint adoption

- [x] 5.1 Add `.swiftlint.yml` enforcing `line_length`, `file_length`, `type_body_length`, and `function_body_length` at the measured worst case present in the tree. Cannot start from a failing test: lint configuration is developer tooling, not runtime behaviour. Verify: `swiftlint` reports zero violations across the package.
- [x] 5.2 Update `DEVELOPMENT.md`: name SwiftLint and `.swiftlint.yml` in the size-limit section with the measured values, and keep the fenced command list exactly matching the commands CI will run. Documentation change, no failing test applies. Verify: the size-limit section names tool and file; the command list matches step 6.1.

## 6. Product CI workflow

- [x] 6.1 Create `.github/workflows/ci.yml`: `macos-15` runner, `actions/checkout` pinned to the same commit SHA as `fleet.yml`, `contents: read` permissions, concurrency group with cancel-in-progress, explicit job timeout; steps `swift build`, `swift test`, `swift build -c release`, launch the release binary with `--smoke`, install and run SwiftLint, and diff the DEVELOPMENT.md fenced command list against the workflow steps, failing on drift. Cannot start from a failing test: the workflow executes only on GitHub-hosted runners. Verify: YAML parses, the file contains the literal `swift test`, `git diff --exit-code .github/workflows/fleet.yml` stays clean.

## 7. Full local gate

- [x] 7.1 Run the complete gate: `swift build`, `swift test`, `swiftlint`, and `openspec validate --all --strict`, all green. This is the cross-cutting verification task spanning all implementation groups above.

## 8. README status accuracy

- [x] 8.1 Update the README status block to state precisely what exists after this change — package scaffold, typed configuration, privacy-redacting logging, menu-bar shell with smoke mode, product CI — and that inbox watching, uploading, Keychain, and notifications do not exist yet. Documentation change, no failing test applies. Verify: the status block matches the proposal's scope with no overclaim.

## 9. Ship

- [ ] 9.1 Commit the work on `feat/app-bootstrap-config-logging` as conventional commits grouped by concern (package+config, logging, app shell, lint+CI, docs). Verify: `git log` shows the grouped history and the worktree diff is fully committed.
- [ ] 9.2 Merge into `main`, push `origin main` (including the earlier `.worktrees` ignore commit), then remove the worktree and delete the feature branch. Verify: remote `main` contains the merge commit; `git worktree list` and the branch list no longer contain this task's entries.
