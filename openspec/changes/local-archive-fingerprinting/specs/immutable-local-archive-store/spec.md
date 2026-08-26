## Purpose

Preserves each accepted candidate's exact original bytes in an agent-owned store addressed by content digest, publishing only through atomic rename so no partial state is ever visible, never rewriting or displacing existing store content, and refusing explicitly when the configured disk budget would be exceeded.

## ADDED Requirements

### Requirement: Preserved copies are content-addressed and byte-verified

The archiver SHALL copy the source into the store under a layout derived from the provider hint and calendar month with the SHA-256 digest as the file name, SHALL verify the copied bytes against the recorded digest before publication, and SHALL leave the original candidate file untouched.

#### Scenario: Archiving preserves verified bytes and the original

- **WHEN** a stable candidate is archived
- **THEN** the store contains a file whose bytes hash exactly to the recorded digest at the digest-addressed path, the reported size matches the source, and the original file still exists unmodified at its original location

### Requirement: Publication is atomic with no visible partial state

Every store write SHALL go through a temporary file inside the destination directory followed by a single rename to the final name. A final path SHALL never exist in a partial state: an interruption during archival leaves either no final entry or a fully published one.

#### Scenario: Interruption mid-copy publishes nothing

- **WHEN** archival is interrupted after some but not all bytes are copied, simulating termination during the move
- **THEN** no entry exists at the final digest-addressed path and the store's visible layout holds no partial archive

#### Scenario: Retry after interruption succeeds

- **WHEN** archival runs again for the same content after the simulated interruption
- **THEN** it completes normally and the published bytes verify against the digest

### Requirement: Existing digests are recognized write-once

Archiving content whose digest already exists in the store SHALL succeed by returning the existing entry without rewriting, truncating, or re-timestamping it, and SHALL NOT overwrite different content under any circumstance; a pre-existing final path whose bytes do not match the expected digest SHALL be reported as an explicit error with the existing file left untouched.

#### Scenario: Duplicate archival reuses the stored entry

- **WHEN** the same content is archived a second time
- **THEN** the same store path is returned, its modification time and inode are unchanged from the first publication, and no temporary files remain

#### Scenario: Mismatched content at an occupied digest path fails explicitly

- **WHEN** the store already holds a file at the target path whose bytes differ from the content being archived
- **THEN** archival fails with an explicit integrity error and the existing file is unchanged

### Requirement: The configured disk budget refuses over-budget archival

The store SHALL enforce a maximum total byte budget from configuration. When current stored bytes plus the incoming archive would exceed the budget, archival SHALL refuse before any copying begins with an explicit over-budget outcome naming the limit; archival within budget SHALL proceed normally.

#### Scenario: Over-budget refusal happens up front

- **WHEN** the store already holds more than the budget minus the incoming file's size
- **THEN** archival returns an explicit over-budget refusal, and no new file or temporary appears anywhere in the store

#### Scenario: Within-budget archival proceeds

- **WHEN** projected usage stays within the budget
- **THEN** archival succeeds and the store total grows by exactly the incoming file's size
