# Proposal: scaffold-macos-app

## Why

The repository holds intent documents only; no code, tests, or product CI exist to verify any future work against. docs/IMPLEMENTATION_PLAN.md plan item 1 asks for exactly this foundation: a buildable macOS app project, typed configuration, unified logging with privacy redaction, test targets, and distribution profiles. Creating the first Swift package also activates the workspace fleet gate that requires a matching `ci.yml` running `swift test`.

## What Changes

- Add an SPM package with three products: the `AgentCore` library (typed configuration), the `AgentLog` library (redacting unified logging), and the `RatatoskrExportAgent` executable.
- The executable runs an AppKit menu-bar agent (`NSApplication` accessory activation policy, no dock icon, no main window) and supports a headless `--smoke` launch mode that exercises the real startup path and exits successfully, for use in CI.
- Introduce the typed configuration file, schema version 1 only: strict decoding that rejects unknown fields, `backendBaseURL` restricted to https except loopback hosts, user-selected `watchedFolders`, and bounded budgets (`maxArchiveBytes`, `maxConcurrentUploads`). A missing file yields documented defaults instead of an error.
- Introduce unified logging built on `os.Logger` with a pure `LogRedactor`: filesystem paths and filenames are removed from messages by default; an explicit local debug/verbose toggle turns redaction off for diagnostics.
- Add XCTest targets for both libraries; behaviours are implemented test-first per repository policy.
- Adopt SwiftLint with `.swiftlint.yml` limits set to the measured worst case already present in the tree; name the tool and its configuration file in the DEVELOPMENT.md size-limit section.
- Add `.github/workflows/ci.yml` (macos-15 runner, SHA-pinned actions, least-privilege permissions, concurrency group, job timeout): debug build, full test run, release build, smoke launch of the release binary, and a sync check between DEVELOPMENT.md commands and the workflow steps.
- Update the README status block to state precisely what exists after this change: scaffold, configuration, and logging only; no inbox watching, uploading, Keychain, or notification behaviour yet.

Out of scope and unchanged: inbox observation, archive fingerprinting, uploads, device authentication/Keychain, reminders and notifications, backend operation tracking.

## Capabilities

### New Capabilities

- `typed-configuration`: Loading, validating, defaulting, and error reporting for the agent's local configuration file.
- `privacy-logging`: Redaction guarantees for log output and the explicit local toggle that relaxes them.
- `app-shell`: Launch behaviour of the agent process: accessory (menu-bar) operation and the headless smoke launch mode.

### Modified Capabilities

None. `openspec/specs/` is intentionally empty; these three capabilities arrive as new deltas.

## Impact

- New files: `Package.swift`, `Sources/AgentCore/`, `Sources/AgentLog/`, `Sources/RatatoskrExportAgent/`, `Tests/AgentCoreTests/`, `Tests/AgentLogTests/`, `.swiftlint.yml`, `.github/workflows/ci.yml`.
- Modified: `DEVELOPMENT.md` (size-limit tool and configuration named; command list kept in sync with CI), `README.md` (status block matches reality).
- Untouched: `.github/workflows/fleet.yml` remains byte-identical across the fleet and must not be edited here.
- No provider, platform, or completeness contracts change; no behaviour visible to other repositories is introduced, so nothing is cited from or added to the ratatoskr-workspace store.
- Development status is honoured: configuration stays at schema version 1 with no version negotiation, no migration machinery, and the product is named Ratatoskr throughout.
