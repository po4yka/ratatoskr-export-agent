## Context

Workspace design D5 sends a checked write of a `cli` connection to a queue that the export agent
reads. The CLI needs installer 1.12.7 or later and a running app; the first command starts the app
when it does not run.

## Decisions

### Ask the app before the CLI

The apply step asks an injected check whether the Obsidian app runs (bundle id `md.obsidian`). Only
then does it run `obsidian version`, once per pass and only when an operation waits. When the app
does not run or the CLI does not answer, the pass ends with `awaitingObsidian`, nothing is applied,
and no result is sent, so notes keeps every operation. A CLI run that gives no answer during an
operation ends the pass in the same way.

### The disk decides the result

The CLI can report success for a command that did nothing. After a `create`, `rename`, `move` or
`delete`, the agent checks the disk: the target exists and the source is gone. The result hash is the
hash of the file on disk after the operation. An `update` or a `create` whose file has the hash of the
content, a `rename` or a `move` whose source is gone and whose target has the base hash, and a
`delete` whose file is gone, are reported as `applied`, so a pass that stopped after the change and
before its result does not raise a false conflict.

### Rename or move

A `rename` that keeps the folder and the extension runs `obsidian rename path=<old> name=<new name
without extension>`. Every other rename and every `move` runs `obsidian move path=<old>
to=<target path>`. Both update the links on the device by the rules of Obsidian; the files whose links
changed reach notes through the watcher.

### Atomic write inside the vault

An `update` writes a temporary file `.ratatoskr-<uuid>.tmp` in the folder of the target and renames it
over the target. The watcher does not report a path with a segment that starts with `.`, so the
temporary file is never sent. The write of the agent comes back through the watcher as one change
with the expected hash, which notes takes as the acknowledgement (workspace design D6); the agent does
not react to its own changes, so nothing loops.

### Base mismatch

A base mismatch gives the local file to the change buffer of the vault, so the one send task of the
sync sends it.
