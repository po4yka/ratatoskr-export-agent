# Developing Ratatoskr Export Agent

> Status: Proposed  
> Last reviewed: 2026-08-20

The bootstrap now includes folder watching, local archive/journal primitives, and Platform device pairing. Upload, reminders, background distribution, signing, and update flow remain unimplemented.

## Intended toolchain

Swift 6, SwiftUI/AppKit where necessary, structured concurrency, FileManager/FileCoordinator, SQLite or another durable local journal, Keychain, URLSession, background scheduling, unified logging, XCTest, Xcode build/signing/notarization.

## Code size limits

SwiftLint carries the size limits through the committed `.swiftlint.yml`; it installs per developer with Homebrew and stays out of `Package.swift` so builds keep their zero-dependency property. Each limit sits at the worst case the tree already has, so the check fails on a regression and not on work that has not been done yet. The measured values today are `line_length` 156 characters, `file_length` 183 lines, `type_body_length` 128 lines, and `function_body_length` 35 lines, with each error threshold one line or character past its warning. Trailing commas in multiline collections are mandatory, matching the formatting applied across the tree.

`ratatoskr-workspace/docs/QUALITY_GATES.md` holds the numbers the repositories with code use today, the command that measured each one, and the limits that were rejected with the reason. Read it before you choose numbers, then measure this tree. Each limit is set at the worst case the tree already has, so that the check fails on a regression and not on work that has not been done yet.

## Workflow

1. Operate only on user-selected inbox/archive directories with persistent scoped access.
2. Detect a completed stable download before hashing or moving it.
3. Hash by streaming, preserve the original immutably, and journal every transition before network upload.
4. Use registered-device credentials from Keychain and idempotent/resumable upload.
5. Test crash/restart, offline, duplicate, partial file, permission loss, low disk, and revocation.

## Platform device pairing evidence

The agent pairs only by exchanging a user-provided code that was approved from a primary Platform session. It sends kind `export_agent` to the configured HTTPS origin; it never automates provider login or uses provider credentials.

The device root secret, bearer credential, and rotating refresh token are held together in a non-synchronizable, device-only macOS Keychain record. Configuration and the journal may hold only origin/device/status metadata. A refresh refusal attempts one device-root recovery; a second refusal clears the Keychain record and puts the agent into re-pairing-required state without touching local archives.

`DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete` is opt-in because a headless CI runner may not grant Keychain access. Run it on a Keychain-capable macOS runner with `RATATOSKR_KEYCHAIN_INTEGRATION=1 build-gate -- swift test --filter DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete`; without that environment value it skips with this exact evidence reason while deterministic injected-store coverage remains mandatory.

The first scaffold PR must document exact Xcode/SwiftPM, test, sandbox, signing, notarization, and local-server commands. The app never needs ChatGPT/Claude passwords or cookies.

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
swiftlint
```
