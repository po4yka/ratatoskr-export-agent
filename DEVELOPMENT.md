# Developing Ratatoskr Export Agent

> Status: Active
> Last reviewed: 2026-08-31

The product runtime now composes folder watching, immutable preservation, mixed-provider journal
routing, Platform device pairing, authenticated operation-bound resumable upload, durable import polling,
gentle local watched-item reminders, and an operational Diagnostics panel. The panel exposes typed
permission, disk, journal, and queue facts and can preview then atomically save a redacted-by-construction support report.
Terminal notices and reminders respect the existing macOS permission decision and never request
permission themselves. The app exposes manual release discovery and has sandbox bundle, signing,
notarization, immutable GitHub Release, and clean-machine acceptance automation with exact policy tests.
Owner credentials, a hosted notarized artifact, a separate-Mac acceptance run, and live
Platform/receiver integration remain pending external evidence.

## Intended toolchain

Swift 6, SwiftUI/AppKit where necessary, structured concurrency, FileManager/FileCoordinator, a durable local journal, Keychain, URLSession, background scheduling, unified logging, XCTest, and Xcode command-line signing/notarization tools.

## Code size limits

SwiftLint carries the size limits through the committed `.swiftlint.yml`; it installs per developer with Homebrew and stays out of `Package.swift` so builds keep their zero-dependency property. Each limit sits at the worst case the tree already has, so the check fails on a regression and not on work that has not been done yet. The measured values today are `line_length` 156 characters, `file_length` 183 lines, `type_body_length` 128 lines, and `function_body_length` 35 lines, with each error threshold one line or character past its warning. Trailing commas in multiline collections are mandatory, matching the formatting applied across the tree.

`ratatoskr-workspace/docs/QUALITY_GATES.md` holds the numbers the repositories with code use today, the command that measured each one, and the limits that were rejected with the reason. Read it before you choose numbers, then measure this tree. Each limit is set at the worst case the tree already has, so that the check fails on a regression and not on work that has not been done yet.

## Workflow

1. Operate only on user-selected inbox/archive directories with persistent scoped access.
2. Detect a completed stable download before hashing or moving it.
3. Hash by streaming, preserve the original immutably, and journal every transition before network upload.
4. Use registered-device credentials from Keychain and idempotent/resumable upload.
5. Test crash/restart, offline, duplicate, partial file, permission loss, low disk, and revocation.

## Resumable upload status

`UploadQueue` holds the durable scheduler-to-uploader link: it streams one configured chunk at a time from the managed local archive, writes every receiver acknowledgement to the journal, resumes a recorded session by querying its status, and uses the SHA-256-derived journal identity on every open attempt. Retryable transport failures receive bounded backoff; permanent failures stop until an explicit retry. The queue admits upload slots and bytes before reading each chunk, and publishes only redacted state/progress for `UploadMenuStatusBinding`.

The fixed blob-transfer fixture and in-process harness are local contract evidence, not live proof. The
authenticated Platform transport is wired into the product runtime, while a receiving-service run remains
pending until those services expose their configured binding.

## Backend import status and notices

`BackendImportStatusMapper` reads only the typed `ai_archive_import_summary` on an
`ai_archive.import` result. Missing or malformed summaries remain unverified; they never become a
complete import. A journal entry retains the Platform operation ID, last valid presentation,
Platform ordering timestamp when present, observed-at timestamp, and terminal-notice delivery bit;
it retains no provider error, path, archive content, filename, count, or credential. A stale
out-of-order `status_changed_at` response cannot replace a newer stored fact, and a repeat that
omits a previously known ordering timestamp cannot erase that fact. Concurrent terminal checks
reserve one delivery before calling macOS, so they cannot duplicate a notice before the durable
delivery marker is written.

The status menu renders a short local ID, generic state and `last known` time only. `UserAgentNotificationService` considers only `authorized` notification permission, never requests it,
and sends generic complete/needs-attention/failed text after a terminal observation is durably
recorded. Its deterministic tests cover denied permission, exactly-once authorized delivery, and
unreachable polling after journal reopen.

## Platform device pairing evidence

The agent pairs only by exchanging a user-provided code that was approved from a primary Platform session. It sends kind `export_agent` to the configured HTTPS origin; it never automates provider login or uses provider credentials.

The device root secret, bearer credential, and rotating refresh token are held together in a non-synchronizable, device-only macOS Keychain record. Configuration and the journal may hold only origin/device/status metadata. A refresh refusal attempts one device-root recovery; a second refusal clears the Keychain record and puts the agent into re-pairing-required state without touching local archives.

`DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete` is opt-in because a headless CI runner may not grant Keychain access. Run it on a Keychain-capable macOS runner with `RATATOSKR_KEYCHAIN_INTEGRATION=1 build-gate -- swift test --filter DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete`; without that environment value it skips with this exact evidence reason while deterministic injected-store coverage remains mandatory.

`docs/DISTRIBUTION.md` documents exact bundle, sandbox, signing, notarization, blocker, recovery, and evidence commands. The app never needs ChatGPT/Claude passwords or cookies.

## What a clone needs before you plan a change

A change is planned with OpenSpec, which is a CLI a clone installs for itself. Use the version
`.github/workflows/openspec.yml` pins, so your terminal and the gate answer the same:

```bash
npm install --global @fission-ai/openspec@1.10.0
```

Cross-repository behaviour lives in a store, and registering one is per-machine state that no
repository can turn on for you — the same kind of step as `git config core.hooksPath .githooks`:

```bash
git clone git@github.com:po4yka/ratatoskr-workspace.git <path>
openspec store register <path> --id ratatoskr-workspace
```

`openspec doctor` reports whether both are in place.

## Commands CI runs

`.github/workflows/ci.yml` executes exactly these project commands on every push, after installing
SwiftLint with Homebrew. Keep this list byte-for-byte in sync with the workflow steps; CI fails when
the two drift apart:

```bash
swift build
swift test
swift build -c release
.build/release/RatatoskrExportAgent --smoke
Tests/Distribution/run.sh
swiftlint
```
