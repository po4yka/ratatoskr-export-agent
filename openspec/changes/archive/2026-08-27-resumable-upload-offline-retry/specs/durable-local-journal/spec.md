## MODIFIED Requirements

### Requirement: Every transition is write-ahead durable
The system SHALL durably append and synchronize each accepted transition before making it observable to its caller. It SHALL accept only `discovered -> archived -> hashed -> queued -> uploading -> uploaded -> confirmed` and SHALL retain an idempotency key derived deterministically from the SHA-256 digest. For a queued or uploading entry, it SHALL also retain only the non-secret resumption token, received chunk indices or equivalent acknowledged progress, retry attempt count, retry eligibility, and queue-control state necessary to resume safely.

#### Scenario: Key survives restart
- **WHEN** a digest reaches `queued`, the process ends, and the journal reopens
- **THEN** the recovered entry remains queued with the same digest-derived key

#### Scenario: Resumption facts survive restart
- **WHEN** an interrupted upload has durably recorded an opaque token, acknowledged chunks, and a next retry time
- **THEN** reopening preserves those facts and does not persist archive bytes, credentials, the user-controlled original source path, or an additional idempotency key; the local-only agent-managed archive path remains available for restart recovery and is never transmitted or rendered
