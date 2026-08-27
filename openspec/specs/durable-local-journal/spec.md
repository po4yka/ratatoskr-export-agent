# durable-local-journal Specification

## Purpose

Makes archive-work lifecycle state durable and replayable across a local agent
crash without guessing at uncertain uploads or double-sending a digest.

## Requirements

### Requirement: Every transition is write-ahead durable
The system SHALL durably append and synchronize each accepted transition before making it observable to its caller. It SHALL accept only `discovered -> archived -> hashed -> queued -> uploading -> uploaded -> confirmed` and SHALL retain an idempotency key derived deterministically from the SHA-256 digest. For a queued or uploading entry, it SHALL also retain only the non-secret resumption token, received chunk indices or equivalent acknowledged progress, retry attempt count, retry eligibility, and queue-control state necessary to resume safely.

#### Scenario: Key survives restart
- **WHEN** a digest reaches `queued`, the process ends, and the journal reopens
- **THEN** the recovered entry remains queued with the same digest-derived key

#### Scenario: Resumption facts survive restart
- **WHEN** an interrupted upload has durably recorded an opaque token, acknowledged chunks, and a next retry time
- **THEN** reopening preserves those facts and does not persist archive bytes, credentials, the user-controlled original source path, or an additional idempotency key; the local-only agent-managed archive path remains available for restart recovery and is never transmitted or rendered

### Requirement: Replay recovers an interrupted upload safely

The system SHALL replay a valid journal into its last consistent projection. On
launch it SHALL convert a durable `uploading` entry to `queued` using the same
idempotency key; it SHALL retain other valid states unchanged.

#### Scenario: Crash after uploading is durable

- **WHEN** the process is interrupted immediately after the `uploading`
  transition is synchronized
- **THEN** launch recovery yields one queued entry with the original key

### Requirement: Corruption is an explicit safe stop

The system SHALL reject malformed, truncated, checksum-invalid, or semantically
inconsistent journal data with a typed safe-stop and SHALL NOT modify the
journal, invent an entry, or schedule an upload from it.

#### Scenario: Truncated final record

- **WHEN** the journal ends with a non-newline-terminated record
- **THEN** recovery fails closed and the source journal bytes remain unchanged

### Requirement: Compaction preserves the projection atomically

The system SHALL compact a journal exceeding its configured bound into a
verified complete snapshot through a same-directory temporary followed by an
atomic replacement. A reopened compacted journal SHALL project the same live
entries.

#### Scenario: Threshold-triggered compaction

- **WHEN** valid history exceeds the configured byte bound
- **THEN** reopening the resulting journal returns the same live entries and
  the on-disk journal is within the bound
