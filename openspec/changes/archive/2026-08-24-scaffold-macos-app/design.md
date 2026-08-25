# Design: scaffold-macos-app

## Context

See proposal.md - Why. The repository has no code yet; this change introduces the first Swift package together with the product CI the workspace fleet gate demands. Constraints that shape the approach: the fleet gate matches a literal `swift test` step in `.github/workflows/ci.yml` the moment `Package.swift` exists; `.github/workflows/fleet.yml` is drift-checked byte-for-byte and must not be edited; development status mandates a single schema/config version with no migration machinery; CI runs on GitHub-hosted `macos-15` runners with a GUI session available.

## Goals / Non-Goals

**Goals:**

- A package that builds, tests, and launches headlessly with plain Swift toolchain commands on a stock runner.
- Behaviour from the three capability deltas pinned by tests written before implementation.
- Zero external package dependencies for the product code.
- Privacy-by-default logging verified by tests, with one explicit escape hatch.
- DEVELOPMENT.md remains the single place where a human can see every command CI runs.

**Non-Goals:**

- Inbox watching, fingerprinting, uploads, device auth, Keychain, reminders, notifications.
- An Xcode project, signing, entitlements, notarization, or distribution packaging.
- Any UI beyond the status-bar item.
- Cross-repository contract changes (nothing to cite from the ratatoskr-workspace store yet).

## Decisions

### D1: SwiftPM package, not an Xcode project

The fleet gate and every planned verification command (`swift build`, `swift test`, release build, binary smoke launch) work on plain SPM. An Xcode project adds opaque mutable state, cannot be exercised by `swift test` alone, and buys nothing until distribution requires entitlements and signing. A generated project (xcodegen) remains the documented future path when that day comes; it is deliberately out of scope here.

### D2: Three targets - two libraries and a thin executable

`AgentCore` owns configuration types and loading; `AgentLog` owns the redactor and logging facade; the `RatatoskrExportAgent` executable composes both and hosts the AppKit shell. Splitting keeps each library independently testable and leaves the executable as a composition root with no logic of its own.

### D3: Configuration model and strict decoding

Configuration is a `Codable` value type decoded by hand: `schemaVersion` is checked to equal 1 before anything else, then the keyed container's key set is compared against the known schema keys, and any extra key aborts decoding naming the offender. This satisfies "unknown fields rejected" without external libraries. Validation rules follow the delta: https-or-loopback endpoint, positive budgets, non-empty folder entries. Defaults when the file is missing: no backend endpoint, empty watched folders, `maxArchiveBytes` = 2 GiB, `maxConcurrentUploads` = 2. Loopback recognition covers exactly `localhost`, `127.0.0.1`, and `::1`. Errors are a typed enum carrying the file location and a reason string; descriptions never embed raw file contents.

Alternatives considered: lenient decoding that ignores unknown keys (violates the intent of surfacing stale configs during development); third-party strict-decoding libraries (unnecessary dependency for a small schema).

### D4: Logging as a pure function behind a thin facade

`AgentLog` exposes a pure redactor - string in, redacted string out - plus a facade that routes formatted messages into unified logging. Redaction recognises absolute POSIX-style paths, home-relative paths (`~/...`), and bare filenames carrying an extension, replacing each with a fixed `<path>` placeholder. Patterns stay deliberately narrow to limit false positives; unit tests pin the boundary cases. Redaction state is injected at construction as a Boolean; tests pass it directly, and the executable resolves it once at startup from a user-defaults key. No command-line flag is added for it in this change, keeping argument handling limited to `--smoke`.

Alternatives considered: redacting inside an `os.Logger` wrapper only (harder to test exhaustively); doing nothing and relying on os_log's `%{private}` (does not cover interpolated message text we control).

### D5: Application shell and smoke mode

The executable brings up `NSApplication` with the accessory activation policy and installs one status-bar item; there is no window. `--smoke` runs the identical startup sequence - policy set, status item installed - then schedules a watchdog that terminates the process with exit code 0 shortly after the running state is reached. Unknown arguments print usage to stderr and exit non-zero. The watchdog bounds runtime so a stuck run loop cannot wedge CI; the workflow's job timeout is the outer backstop.

### D6: SwiftLint adoption without a package dependency

Linting stays out of `Package.swift` to preserve the zero-dependency property and offline builds; SwiftLint is installed per-developer (Homebrew) and in CI via Homebrew on the runner. `.swiftlint.yml` sets `line_length`, `file_length`, `type_body_length`, and `function_body_length` to the measured worst case already present in the tree, per the workspace quality-gate method; DEVELOPMENT.md names the tool and the file in its size-limit section. Drifting linter versions are treated as fix-forward noise because the hard size ceilings live in the committed config either way.

### D7: CI workflow shape

`.github/workflows/ci.yml` runs on `macos-15` with `actions/checkout` pinned to the same commit SHA fleet.yml uses, `contents: read` permissions, a concurrency group, and an explicit job timeout. Steps: `swift build`, `swift test` (the gate-matching line), `swift build -c release`, launch the release binary with `--smoke`, install SwiftLint and run it, then a final step that diffs the command list fenced in DEVELOPMENT.md against the workflow's run steps and fails on drift. No caching layers in the first cut; add them only if wall-clock becomes a problem.

## Risks / Trade-offs

- [Headless AppKit startup misbehaves on runners] -> smoke exercises exactly what CI runs, the watchdog bounds it, and the job timeout is the second net; the smoke path is kept minimal (policy + status item, no event-loop pumping beyond reaching running state).
- [Redactor false positives mangle ordinary text] -> narrow anchored patterns, boundary-case unit tests, and the verbose toggle as the diagnostic escape hatch.
- [Strict unknown-field rejection annoys early users] -> intentional during development status; the error names the offending field so fixes are mechanical.
- [Homebrew SwiftLint version drift in CI] -> the committed `.swiftlint.yml` carries the enforcing limits; upgrades that surface new violations are fixed forward rather than pinned silently.
- [Watchdog turns a hang into a false success] -> exit code 0 is emitted only after the status item is confirmed installed; anything else exits non-zero, and the timeout catches the residue.

## Migration Plan

Not applicable - there is no existing code, data, or workflow to migrate. Rollback is reverting the single merge commit; the change creates no persisted state.
