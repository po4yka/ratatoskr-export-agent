## 1. Rename pairing (workspace OBS-023 tasks 12.1 and 12.2)

- [x] 1.1 RED: `Tests/AgentCoreTests/VaultWatcherTests.swift` `testDeleteAndCreateWithEqualHashIsRename` feeds a delete and a create with equal hashes and asserts one `renamed` change. Confirm that it fails because the vault watcher does not exist (a stub that returns no change, so the failure is the assertion and not a compile error).
- [x] 1.2 GREEN: implement the vault mode with FSEvents, the Obsidian CLI rename check, and the same batch format as the plugin. Verify 1.1.

## 2. Gate

- [x] 2.1 Run `swift build`, `swift test`, `swift build -c release`, the release `--smoke` launch, `Tests/Distribution/run.sh`, `swiftlint`, and `openspec validate --all --strict`. A gate run is not a behaviour and cannot start from a failing test. `openspec validate --all --strict` also fails on `main` for three items that this change does not touch (two specs and `xr-021-r5-classify-platform-answers`, a requirement longer than 500 characters); `obs-023-vault-mode` is valid.
