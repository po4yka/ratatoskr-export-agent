## Why

OBS-024 (`ratatoskr-workspace` change `add-notes-write-back`, group 12, tasks 12.1 and 12.2, design
D5) lets Ratatoskr change a connected vault. For a `cli` connection, `ratatoskr-notes` keeps the
checked writes in a queue of the connection, and the export agent must apply them on the Mac and
report each result. Today the agent only sends changes; it cannot read the queue.

## What Changes

- A queue reader in `AgentCore` reads
  `GET /v1/notes/connections/{id}/device-operations?after=<cursor>` in pages of at most 256, reads the
  bytes of an operation from `.../device-operations/{operation_id}/content`, and reports each result
  with `POST .../device-operations/{operation_id}/result`. When notes answers `409`
  `notes.channel.bytes_missing`, the agent uploads the bytes and sends the result again.
- The apply step compares the hash of the local file with the base hash first. It applies `create`,
  `rename`, `move`, `delete` and `set_property` with the Obsidian CLI, and `update` with an atomic
  write into the vault folder. It never passes `permanent` to `obsidian delete`.
- The agent does not ask the CLI while the Obsidian app does not run, because the CLI starts the app.
  Then every operation stays in the queue.
- A path that resolves outside the vault, or that has a segment that starts with `.`, is refused.
- The HTTPS binding of the notes routes sends the query of a path as a query.

## Capabilities

### New Capabilities

- `vault-write-back`: the export agent applies the queued writes of a `cli` connection to the vault.

## Impact

- Cites the workspace specs `notes-write-delivery` and `notes-device-channels` instead of restating
  them.
- The real Obsidian CLI and the owner's vaults are never used in tests. The tests use a fake
  `obsidian` executable that records its arguments, a temporary vault and `FakeNotesServer`.
