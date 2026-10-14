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
- `VaultChangeBatch` encodes changes in the batch format of the plugin channel, at most 256 changes
  in one batch.

## Capabilities

### New Capabilities

- `vault-mode`: the export agent watches an Obsidian vault and produces change batches for the
  `cli` channel.

## Impact

- Affects `AgentCore` only. No UI, pairing, connect call, blob upload or batch send is wired in this
  change. Those need the notes routes of OBS-023 group 8, which do not exist yet.
- Cites the workspace spec `notes-device-channels` (batch bounds, sequence, kinds) instead of
  restating it.
- The real Obsidian CLI is never run in tests. The machine of the spike had installer 1.8.10, and
  the CLI needs 1.12.7 or later.
