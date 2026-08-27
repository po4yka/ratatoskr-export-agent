# resumable-archive-upload Specification

## Purpose
Transfers a preserved export through the shared digest-first blob receipt protocol so network interruption cannot duplicate or silently corrupt an archive.

## Requirements

### Requirement: Archive sessions are digest-first and bounded
Before sending archive bytes, the agent SHALL open a receipt session that declares the preserved archive's byte size, SHA-256 digest, media type, digest-derived idempotency key, and a valid fixed chunk size. It SHALL stream one chunk at a time from the preserved local copy and SHALL NOT load the complete archive into memory.

#### Scenario: Opening a multi-chunk archive sends no payload bytes
- **WHEN** the agent starts an upload for a preserved archive larger than one chunk
- **THEN** the harness records a valid digest-first session declaration before any chunk request, and each later chunk has the declared index and expected bounded byte length

### Requirement: Interrupted transfers resume from receipt status
After an interrupted or uncertain request, the agent SHALL obtain the receipt status for its durable opaque resumption token before sending another chunk. It SHALL send only indices missing from that status view and retain the received-byte progress derived from acknowledged indices.

#### Scenario: Resume at a chunk boundary avoids replaying acknowledged chunks
- **WHEN** a harness interrupts an upload immediately after acknowledging chunk index one
- **THEN** the later retry queries status and sends indices two and later without re-sending indices zero or one

### Requirement: Digest identity prevents duplicate remote imports
The agent SHALL use the deterministic journal idempotency key derived from the archive SHA-256 for every session attempt. If a session is already finalized for that identity, it SHALL retain the returned archive reference and SHALL NOT open or finalize a duplicate import.

#### Scenario: Retrying after an acknowledged finalize returns one receipt
- **WHEN** the connection fails after the receiver has finalized an archive and the agent retries the same digest
- **THEN** the harness observes one finalized receipt for that digest and the local entry reaches uploaded using that receipt

### Requirement: Completion is verified before upload success is exposed
The agent SHALL treat an upload as completed only when the receiver reports a stored outcome whose byte count and SHA-256 match the local fingerprint. A mismatch, conflict, validation refusal, or policy refusal SHALL leave the local archive and journal identity intact and SHALL not be surfaced as a successful upload.

#### Scenario: Mismatched final receipt is not successful
- **WHEN** the harness returns a stored outcome with a digest different from the local fingerprint
- **THEN** the agent records a non-retriable upload failure and exposes no uploaded success state

### Requirement: Fixed contract fixtures precede service integration
Until an authenticated Platform edge and receiving archive service are available, the agent SHALL validate its receipt encodings and harness interactions against committed fixed blob-transfer fixtures. It SHALL mark live integration as pending rather than treating the harness as live proof.

#### Scenario: Fixture-compatible session declaration is emitted
- **WHEN** a synthetic archive begins upload
- **THEN** its session declaration decodes to the committed valid multi-chunk fixture shape and no live endpoint is required by the test suite
