# Developing Ratatoskr Export Agent

> Status: Proposed  
> Last reviewed: 2026-08-20

Architecture bootstrap: the macOS app/background component, watcher, journal, Keychain integration, uploader, signing, and update flow are not implemented.

## Intended toolchain

Swift 6, SwiftUI/AppKit where necessary, structured concurrency, FileManager/FileCoordinator, SQLite or another durable local journal, Keychain, URLSession, background scheduling, unified logging, XCTest, Xcode build/signing/notarization.

## Code size limits

There is no code here yet, so no limit is enforced yet. This is also one of the two repositories whose first code is Swift or Kotlin, and the fleet has chosen no linter for either language. `fleet.yml` asserts that a `Cargo.toml` arrives with a `clippy.toml` and that a `package.json` arrives with an `eslint.config.js`. It can assert nothing for a `Package.swift` or a `build.gradle.kts`, because there is no fleet answer to name. The scaffold pull request here names the tool and the file that carry the limits, and adds that assertion to `fleet.yml` in all seventeen repositories.

`ratatoskr-workspace/docs/QUALITY_GATES.md` holds the numbers the repositories with code use today, the command that measured each one, and the limits that were rejected with the reason. Read it before you choose numbers, then measure this tree. Each limit is set at the worst case the tree already has, so that the check fails on a regression and not on work that has not been done yet.

## Workflow

1. Operate only on user-selected inbox/archive directories with persistent scoped access.
2. Detect a completed stable download before hashing or moving it.
3. Hash by streaming, preserve the original immutably, and journal every transition before network upload.
4. Use registered-device credentials from Keychain and idempotent/resumable upload.
5. Test crash/restart, offline, duplicate, partial file, permission loss, low disk, and revocation.

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
