## Why

OBS-023 (`ratatoskr-workspace` change `add-notes-vault-connections`, tasks 12.1 and 12.2, design D5
and D6) adds the `cli` channel: on macOS, the export agent sends the file changes of an Obsidian
vault without Obsidian Sync and without the plugin. The agent has no vault mode today.

## What Changes

- A vault mode in `AgentCore` watches one vault folder with FSEvents, reads the changed files from
  disk, and computes the SHA-256 and the byte length of each file.
- `VaultWatcher` turns the observations into ordered changes of kind `created`, `updated`,
  `renamed` and `deleted`, with the device change sequence. It pairs a create and a delete with equal
  hashes within 3 seconds into one `renamed` change, in either order (design D5).
- The Obsidian CLI rename check is behind a protocol. When the CLI is not installed, the app does not
  run, or the answer is not clear, the check is unavailable and the agent keeps the hash pairing.
- Paths are NFC and relative to the vault root. A path with a segment that starts with `.`
  (`.obsidian/`, `.trash/`, `.DS_Store`) is not reported, as the vault API of the plugin does not
  report it.
- `VaultModeCoordinator` connects the event source, the scanner and the watcher. At start it reads
  the whole vault and returns the manifest (every indexed path with its hash), which the device sends
  when it cannot prove that it saw every change. Lost FSEvents events make it compare the whole vault.
- `VaultChangeBatch` encodes changes in the batch format of the plugin channel, at most 256 changes
  in one batch.

## Capabilities

### New Capabilities

- `vault-mode`: the export agent watches an Obsidian vault and produces change batches for the
  `cli` channel.

## Impact

- Affects `AgentCore` only. Groups 4 to 6 of the tasks (workspace tasks 12.5 to 12.10) add the
  client of the notes routes of OBS-023 group 8: the connect, the manifest, the uploads and the
  change batches, and `VaultChannelSync`, which sends a watched vault through it. No UI, vault
  configuration or app start of the vault mode is wired in this change.
- Cites the workspace spec `notes-device-channels` (batch bounds, sequence, kinds) instead of
  restating it.
- The real Obsidian CLI is never run in tests. The machine of the spike had installer 1.8.10, and
  the CLI needs 1.12.7 or later.
