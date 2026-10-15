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
