## ADDED Requirements

### Requirement: An outside rename is one renamed change

The agent SHALL pair a delete and a create of two different paths with equal SHA-256 that occur
within 3 seconds of each other, in either order, into one `renamed` change with the old path. The
agent SHALL send a delete or a create that has no pair after 3 seconds as it is.

#### Scenario: A delete and a create with equal hashes

- **WHEN** the watcher records a delete of `Notes/Old.md` and, 1 second later, a create of `Notes/New.md` with the same hash
- **THEN** it gives exactly one `renamed` change from `Notes/Old.md` to `Notes/New.md`, verified by `Tests/AgentCoreTests/VaultWatcherTests.swift` `testDeleteAndCreateWithEqualHashIsRename`

#### Scenario: The spike order, create first

- **WHEN** the watcher records a create and, 1 second later, a delete with the same hash
- **THEN** it gives exactly one `renamed` change, verified by `VaultWatcherTests.testCreateThenDeleteOneSecondLaterIsRename`

#### Scenario: Too far apart

- **WHEN** a delete and a create with the same hash are more than 3 seconds apart
- **THEN** the watcher gives one `deleted` and one `created` change, verified by `VaultWatcherTests.testEqualHashOutsideWindowIsNotPaired`

### Requirement: The Obsidian CLI can refute a rename, and its absence changes nothing

When the Obsidian CLI rename check is available and refutes a pair, the agent SHALL send the delete
and the create as they are. When the check is unavailable, the agent SHALL keep the hash pairing.

#### Scenario: The CLI says the old path still exists

- **WHEN** the rename check refutes a hash pair
- **THEN** the watcher gives one `deleted` and one `created` change, verified by `VaultWatcherTests.testRefutedPairIsNotRename`

#### Scenario: The CLI is not installed

- **WHEN** no `obsidian` executable is found
- **THEN** the check answers unavailable, and a hash pair is still one `renamed` change, verified by `ObsidianCLIRenameCheckTests.testMissingExecutableIsUnavailable`

### Requirement: A batch has the plugin format

A batch SHALL hold at most 256 changes, in sequence order. Each change SHALL encode `sequence`,
`kind`, the NFC `path`, `previous_path` for `renamed`, and `sha256` and `byte_length` except for
`deleted`.

#### Scenario: A renamed change is encoded

- **WHEN** a batch with one `renamed` change is encoded
- **THEN** the JSON has exactly the keys `sequence`, `kind`, `path`, `previous_path`, `sha256` and `byte_length`, verified by `VaultChangeBatchTests.testRenamedChangeHasPluginKeys`

#### Scenario: 257 changes

- **WHEN** 257 changes are split into batches
- **THEN** the first batch holds 256 changes and the second holds 1, verified by `VaultChangeBatchTests.testSplitsAt256`
