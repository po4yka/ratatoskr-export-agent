# Developing Ratatoskr Export Agent

> Status: Proposed  
> Last reviewed: 2026-08-17

Architecture bootstrap: the macOS app/background component, watcher, journal, Keychain integration, uploader, signing, and update flow are not implemented.

## Intended toolchain

Swift 6, SwiftUI/AppKit where necessary, structured concurrency, FileManager/FileCoordinator, SQLite or another durable local journal, Keychain, URLSession, background scheduling, unified logging, XCTest, Xcode build/signing/notarization.

## Workflow

1. Operate only on user-selected inbox/archive directories with persistent scoped access.
2. Detect a completed stable download before hashing or moving it.
3. Hash by streaming, preserve the original immutably, and journal every transition before network upload.
4. Use registered-device credentials from Keychain and idempotent/resumable upload.
5. Test crash/restart, offline, duplicate, partial file, permission loss, low disk, and revocation.

The first scaffold PR must document exact Xcode/SwiftPM, test, sandbox, signing, notarization, and local-server commands. The app never needs ChatGPT/Claude passwords or cookies.
