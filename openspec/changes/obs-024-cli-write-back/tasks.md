## 1. The `cli` channel applies queued writes (workspace OBS-024 tasks 12.1 and 12.2)

- [x] 1.1 RED: add `Tests/AgentCoreTests/ObsidianCliApplyTests.swift` with `testRenameUsesObsidianRename`, `testDeleteNeverPermanent` and `testClosedObsidianLeavesQueue`, against a fake `obsidian` executable that records its arguments, and `Tests/AgentCoreTests/NotesChannelHTTPTests.swift` `testQueryOfThePathIsSentAsAQuery`. Confirm that all fail by their assertions (stubs apply nothing and report a pass that answered nothing, and the binding encodes `?` into the path).
- [x] 1.2 GREEN: implement the queue reader and the CLI apply step, keep the query of a path in the HTTPS binding, and read the queue from each vault sync. Verify 1.1 and the full suite, and document the requirement of Obsidian 1.12.7 or later in `README.md`.

## 2. Gate

- [x] 2.1 Run the gates of `ci.yml`, the DEVELOPMENT.md drift check, the 8 steps of the workspace `reusable-fleet.yml`, `zizmor .github/workflows` and `openspec validate obs-024-cli-write-back --strict`. A gate run is not a behaviour and cannot start from a failing test.
