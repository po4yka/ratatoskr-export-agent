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

### Unsafe paths

A refused path is reported as `failed` with `notes.write.unsafe_path`, before the agent reads the
content or runs the CLI.

### The hash after `property:set`

Obsidian can write the frontmatter after the CLI returned. When the file still has the base hash after
`property:set` or `property:remove`, the agent waits once (0.5 s) and reads the hash again.

### The CLI thread

The CLI runner blocks until the process ends, for up to 30 seconds. Each run is on a dedicated
thread named `obsidian-cli`, and the pass awaits it through a continuation, so no thread of the
cooperative pool waits for Obsidian.

### Local errors and transport errors

An error of the content read is a transport error: the pass ends, and the operation stays in the
queue for the next pass. Any other error of the apply step (a folder at the path, a failed write, bytes
that do not match their digest) settles the operation as `failed` with `notes.channel.refused`, the
code of the plugin, and the pass goes on with the next operation.

### An unfinished create

`obsidian create` makes an empty file before the agent writes the bytes. When the CLI times out, or
the write fails, an empty file stays. A later `create` with no base that finds an empty file at its
path takes it as its own and writes the bytes without the CLI. A user file that is empty by chance is
then replaced; the base of a create says that notes knows no file there.

### The content bound

The content read carries `length_bytes` as its bound. The HTTPS binding reads the body as a stream
and stops after the bound and one byte, so the agent never holds more. Content longer than
`length_bytes` is refused before its digest is computed.

### A rename with its link rewrites

Notes lists a rename or a move with `rewrites`: the path, the base hash and the expected hash of each
linking note. Before the CLI, the agent checks the path and the base hash of each note; a refused path
fails the group with `notes.write.unsafe_path`, and a base mismatch refuses the group with a top-level
`base_mismatch` (no `local_sha256`, because the mismatch is not in the renamed file) and gives the note
to the change buffer. After the CLI, the agent hashes each note (once more after `settle` when a note
still has its base hash), uploads each hash that is not the expected hash, and lists the notes in the
`rewrites` of the `applied` result. A note that is gone is listed as `base_mismatch`. The agent has no
plain-move path: a rename or a move always runs the Obsidian CLI, which updates the links.
