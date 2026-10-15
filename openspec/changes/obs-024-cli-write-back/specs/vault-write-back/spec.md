## ADDED Requirements

### Requirement: The agent applies a queued rename with the Obsidian CLI

The agent SHALL apply a `rename` that keeps the folder and the extension with `obsidian rename`, so
that Obsidian updates the links (workspace spec `notes-write-delivery`).

#### Scenario: A rename through the CLI

- **WHEN** the queue holds `rename` of `Projects/Alpha.md` to `Projects/Apollo.md` with the hash of the local file as its base
- **THEN** the agent runs `obsidian vault=<name> rename path=Projects/Alpha.md name=Apollo` once and reports `applied` with the hash of `Projects/Apollo.md`, verified by `Tests/AgentCoreTests/ObsidianCliApplyTests.swift` `testRenameUsesObsidianRename`

### Requirement: A delete goes to the trash

The agent SHALL NOT pass `permanent` to `obsidian delete`.

#### Scenario: A delete through the CLI

- **WHEN** the queue holds `delete` of `Notes/Old.md`
- **THEN** the recorded CLI arguments do not contain `permanent`, and the agent reports `applied`, verified by `ObsidianCliApplyTests.testDeleteNeverPermanent`

### Requirement: A closed Obsidian leaves the queue

When the Obsidian app does not run, the agent SHALL NOT run the CLI, SHALL NOT change the vault, and
SHALL NOT report a result.

#### Scenario: Obsidian is closed

- **WHEN** the agent reads the queue while the Obsidian app does not run
- **THEN** the pass ends as awaiting Obsidian, the CLI does not run, the file does not change, and no result is sent, verified by `ObsidianCliApplyTests.testClosedObsidianLeavesQueue`

### Requirement: The HTTPS binding keeps the query of a path

The HTTPS binding of the notes routes SHALL send the part of a path after `?` as the query of the URL.

#### Scenario: The queue cursor

- **WHEN** the client reads `v1/notes/connections/c1/device-operations?after=7`
- **THEN** the URL is `https://ratatoskr.example/v1/notes/connections/c1/device-operations?after=7`, verified by `NotesChannelHTTPTests.testQueryOfThePathIsSentAsAQuery`

### Requirement: An unsafe path is refused

The agent SHALL report `failed` with `notes.write.unsafe_path`, and SHALL NOT read the content or
change a file, for a path that is absolute, that has an empty, `.` or `..` segment or a segment that
starts with `.`, whose nearest existing folder resolves outside the vault, or that is a symbolic link.

#### Scenario: Seven unsafe paths

- **WHEN** the queue holds updates of `/etc/x.md`, `../x.md`, `A//B.md`, `./A.md`, `.obsidian/app.json`, `Link/x.md` (a link to a folder outside the vault) and `Leak.md` (a link to a file outside the vault)
- **THEN** each result is `failed` with `notes.write.unsafe_path`, and the file outside the vault does not change, verified by `ObsidianCliApplyPathTests.testUnsafePathsFailWithUnsafePath`

### Requirement: The hash after `property:set` is the hash of the changed file

After `obsidian property:set` or `property:remove`, when the file still has the base hash, the agent
SHALL wait once and read the hash again before it reports the result.

#### Scenario: Obsidian writes the frontmatter late

- **WHEN** the file changes only after the CLI returned
- **THEN** the result has the hash of the changed file, verified by `ObsidianCliApplyResultTests.testSetPropertyReadsTheHashAgainWhenTheFileDidNotChangeYet`

### Requirement: The CLI holds no thread of the cooperative pool

The agent SHALL run each Obsidian CLI command on a dedicated thread.

#### Scenario: The thread of a CLI run

- **WHEN** the agent runs the CLI for a pass
- **THEN** each run is on a thread named `obsidian-cli`, verified by `ObsidianCliApplyResultTests.testTheCLIRunsOnItsOwnThread`

### Requirement: The menu shows a vault that waits for Obsidian

While operations of the queue wait and the Obsidian app does not run, the status of the vault SHALL be
`awaitingObsidian`, and the menu SHALL show `Vault <name>: waits for Obsidian`.

#### Scenario: Obsidian is closed with a write in the queue

- **WHEN** a pass finds an operation while the app does not run
- **THEN** the sync status is `awaitingObsidian` and the title is `Vault <name>: waits for Obsidian`, verified by `VaultSyncObsidianStatusTests.testAPassThatWaitsForObsidianShowsInTheStatus` and `VaultStatusMenuProjectionTests.testAVaultThatWaitsForObsidianHasItsTitle`

### Requirement: Separators, control characters and trailing dots are refused

The agent SHALL report `failed` with `notes.write.unsafe_path` for a path or a target path that holds
`\`, `:`, a C0 control character or DEL, a segment that ends in `.` or a space, or a first segment
`.obsidian` in any case, before it reads the content or runs the CLI.

#### Scenario: Twelve unsafe paths

- **WHEN** the queue holds updates of `A\.obsidian\plugins\x.md`, `..\x.md`, `A\u{0}.md`, `A\nB.md`, `A\u{7F}.md`, `Notes/.. /x.md`, `Notes/. /x.md`, `A:B.md`, `Notes./x.md` and `Notes /x.md`, and moves to `Notes\B.md` and `Notes/B:C.md`
- **THEN** each result is `failed` with `notes.write.unsafe_path`, only `obsidian version` runs, and nothing is written, verified by `ObsidianCliApplyPathTests.testBackslashesControlCharactersColonsAndTrailingDotsFailWithUnsafePath`

### Requirement: A local error settles the operation

An error of the apply step that is not an error of the content read SHALL settle the operation as
`failed` with `notes.channel.refused`, and the pass SHALL go on with the next operation. An error of
the content read SHALL end the pass and leave the operation in the queue.

#### Scenario: A folder at the path

- **WHEN** the queue holds an update of `Folder.md`, which is a folder, and then an update of `A.md`
- **THEN** the first result is `failed` with `notes.channel.refused`, and `A.md` is applied in the same pass, verified by `ObsidianCliApplyLocalTests.testALocalErrorFailsTheOperationAndThePassGoesOn`

### Requirement: A base mismatch changes nothing

When the local file does not have the base hash, the agent SHALL NOT read the content, SHALL NOT run
a CLI command for the operation, SHALL report `base_mismatch` with the local hash, and SHALL give the
local file to the change buffer.

#### Scenario: A newer local edit

- **WHEN** the queue holds an update of `A.md` whose base is not the hash of the local file
- **THEN** the file does not change, the result is `base_mismatch` with `local_sha256`, and the change buffer gets an `updated` change of `A.md`, verified by `ObsidianCliApplyLocalTests.testBaseMismatchChangesNothingAndSendsTheLocalFile`

### Requirement: An update is an atomic write

After a base match, the agent SHALL write the bytes of an `update` through a new file that it renames
over the old one, and SHALL report the hash of the written file.

#### Scenario: An update

- **WHEN** the queue holds an update of `A.md` with the hash of the local file as its base
- **THEN** `A.md` has the new bytes in a new file, no temporary file is left, and the result has their hash, verified by `ObsidianCliApplyLocalTests.testUpdateWritesTheBytesAtomicallyAfterABaseMatch`

### Requirement: `set_property` passes the value with its type, after a digest check

The agent SHALL check the bytes of a `set_property` against their digest, SHALL run `property:set`
with the value and its type (`number`, `checkbox` or `list`; none for a string), and SHALL run
`property:remove` with the name.

#### Scenario: Four values

- **WHEN** the queue sets a string, a number, a boolean and a list
- **THEN** the CLI arguments carry `type=number`, `type=checkbox` and `type=list` (items joined with `, `), verified by `ObsidianCliPropertyTests.testSetPassesTheValueAndItsType` and `ObsidianCliPropertyTests.testRemovePassesTheName`

#### Scenario: Bytes that do not match their digest

- **WHEN** the content of a `set_property` does not have the hash of its digest
- **THEN** the result is `failed` with `notes.channel.refused` and no CLI command runs for it, verified by `ObsidianCliPropertyTests.testSetPropertyContentIsCheckedAgainstItsDigest`

### Requirement: An unfinished create is finished

When a `create` with no base finds an empty file at its path, the agent SHALL take it as the file of
its own earlier `obsidian create`, SHALL write the bytes without running the CLI again, and SHALL
report `applied` with their hash.

#### Scenario: The write after `obsidian create` did not happen

- **WHEN** a create of `New/Note.md` finds an empty `New/Note.md`
- **THEN** the file has the bytes, no CLI command runs for it, and the result is `applied`, verified by `ObsidianCliApplyLocalTests.testAnEmptyFileOfAnUnfinishedCreateIsFinished`

### Requirement: The content read is bounded by its length

The agent SHALL read the content with `length_bytes` as the bound, the HTTPS binding SHALL read at
most the bound and one byte, and content longer than `length_bytes` SHALL make the operation `failed`
with `notes.channel.refused`.

#### Scenario: Content longer than its length

- **WHEN** the content of an update has 4 bytes and `length_bytes` 3
- **THEN** the result is `failed` with `notes.channel.refused`, the file does not change, and the read carries the bound 3, verified by `ObsidianCliApplyLocalTests.testContentLongerThanItsLengthIsRefused` and `NotesChannelHTTPTests.testABoundedBodyIsReadUpToItsBoundAndOneByte`

### Requirement: A rename with its link rewrites is one group

For a `rename` or a `move` that lists `rewrites`, the agent SHALL check the path and the base hash of
each linking note before the CLI, and SHALL refuse the whole group when one check fails. After the
CLI, it SHALL report the hash of each linking note in the `rewrites` of the `applied` result, and
SHALL upload first each hash that is not the `expected_sha256` of its note.

#### Scenario: Obsidian rewrites two linking notes

- **WHEN** the queue renames `Projects/Alpha.md` with two linking notes, and one note does not get its expected bytes
- **THEN** the result lists both notes as `applied` with their hashes, and only that one note is uploaded, before the result, verified by `ObsidianCliRewriteTests.testRenameReportsTheHashOfEachLinkingNote`

#### Scenario: A linking note has a newer local edit

- **WHEN** a linking note does not have its base hash
- **THEN** the result is `base_mismatch` with the hash of the renamed file and a `base_mismatch` entry with its own hash for every listed linking note, no CLI command runs, and the notes that differ go to the change buffer, verified by `ObsidianCliRewriteTests.testARewriteBaseMismatchRefusesTheGroupBeforeTheCLI`

#### Scenario: An unsafe linking note

- **WHEN** a linking note has the path `../Index.md`
- **THEN** the result is `failed` with `notes.write.unsafe_path`, and no CLI command runs, verified by `ObsidianCliRewriteTests.testAnUnsafeRewritePathFailsTheGroup`

### Requirement: A result is sent again until notes takes it

The agent SHALL keep each result that did not get `200` (or `404` `notes.device_operation.not_found`)
and SHALL send the same result again on the next pass, without a new apply.

#### Scenario: A server error on the result

- **WHEN** notes answers `503` to the result of a `set_property`
- **THEN** the next pass sends the same `applied` result, and the property is set once, verified by `ObsidianCliResendTests.testAResultIsSentAgainAfterAServerError`

#### Scenario: A network error on the result

- **WHEN** the result of a rename meets a network error
- **THEN** the next pass reports the rename as `applied`, and the file is renamed once, verified by `ObsidianCliResendTests.testAResultIsSentAgainAfterANetworkError`

### Requirement: A kept result survives a restart and a refused one is dropped

The agent SHALL keep each result that notes did not take in a file of its support directory, SHALL
send it again after a restart, and SHALL drop it and apply again when notes answers a `4xx` other than
`409` or when its bytes are stale.

#### Scenario: A restart after a server error

- **WHEN** a result gets `503` and the agent restarts
- **THEN** the new client sends the same result, and the property is set once, verified by `ObsidianCliRestartTests.testAKeptResultSurvivesARestart`

#### Scenario: Notes refuses a kept result

- **WHEN** notes answers `400` to a kept result
- **THEN** the next pass applies the operation again, verified by `ObsidianCliRestartTests.testAKeptResultThatNotesRefusesIsDroppedAndAppliedAgain`

### Requirement: A group refusal of the renamed file names every linking note

When the renamed file of a group does not have its base hash, the agent SHALL send the group refusal
with the hash of the file and every linking note with its own hash.

#### Scenario: The renamed file has a newer edit

- **WHEN** a rename with one linking note finds a newer edit in the renamed file
- **THEN** the result is `base_mismatch` with the hash of the file and the note as `base_mismatch` with its own hash, verified by `ObsidianCliRewriteTests.testAFileMismatchWithRewritesNamesEveryLinkingNote`

### Requirement: A moved file with the expected hash is already applied

A `rename` or a `move` whose source is gone and whose target has the `expected_sha256` or the base hash
SHALL be reported as `applied` without a CLI command.

#### Scenario: Obsidian rewrote a link in the renamed file

- **WHEN** the target has the expected hash of the rename, which differs from its base hash
- **THEN** the result is `applied` with that hash and no CLI command runs, verified by `ObsidianCliRestartTests.testAMovedFileWithItsExpectedHashIsAlreadyApplied`
