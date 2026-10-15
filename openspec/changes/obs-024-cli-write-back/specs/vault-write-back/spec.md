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
