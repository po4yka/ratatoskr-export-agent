## Context

Workspace design D6 gives the export agent a vault mode for the `cli` channel. It watches the vault
with FSEvents, reads files from disk, uses the Obsidian CLI only to confirm renames, and sends the
same batch format as the plugin (design D5). Spike 3.5 found that a rename outside Obsidian arrives
as a create and, about 1 second later, a delete.

## Decisions

### The disk decides, FSEvents only names the paths

FSEvents flags are coalesced and do not prove what happened. The event source gives only the changed
paths. `VaultScanner` compares each path with the last known index (path to hash and length) and the
disk: a new file is `created`, a different hash is `modified`, a missing file is `deleted`. A
directory path, or a flag that asks for a rescan, makes the scanner compare the full subtree. So a
folder rename becomes one delete and one create per file, and the hash pairing makes one `renamed`
change per file.

### VaultWatcher is a pure value

`VaultWatcher` takes observations with an explicit time and gives changes when `drain(at:)` is
called. Tests use no clock and no file system. An unpaired create or delete waits 3 seconds. Changes
leave in the order of observation, so a later change never has a lower sequence than an earlier
change to the same path.

### The CLI check can only refute

`VaultRenameChecking` answers `confirmed`, `refuted` or `unavailable` for a hash pair. Only
`refuted` splits the pair. The real `ObsidianCLIRenameCheck` runs `obsidian vault=<name> file
path=<path>` for the old path through an injected runner with a time limit. Exit status 0 means
that Obsidian still knows the old path, so the pair is refuted. Any other answer, a missing
executable, a time-out or a failure to start is `unavailable`. The command shape comes from the
Obsidian CLI documentation and is not measured: the spike machine had installer 1.8.10.

### Batches

`VaultChangeBatch` holds at most 256 changes and encodes `{"changes": [...]}` with the keys of the
workspace spec `notes-device-channels`. The sequence starts at the value that the caller gives, which
is the committed sequence plus 1 after a restart.
