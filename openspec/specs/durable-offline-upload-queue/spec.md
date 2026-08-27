# durable-offline-upload-queue Specification

## Purpose
Keeps preserved archives safely queued across offline periods while bounding retry frequency, upload concurrency, and aggregate network use.

## Requirements

### Requirement: Retryable transfer failures remain durably queued
On reachability loss, transport interruption, timeout, or a receiver-declared retryable failure, the agent SHALL persist a queued retry state before reporting it. The state SHALL retain only the non-secret archive identity, resumption facts, attempt count, and next eligible retry time, and it SHALL survive restart.

#### Scenario: Offline attempt survives restart
- **WHEN** an upload attempt fails because the harness is offline and the queue is reopened
- **THEN** the same digest is queued with its retry time and no archive bytes or credentials are stored in queue state

### Requirement: Retry timing is bounded and does not spin
The agent SHALL use bounded exponential backoff with deterministic injectable jitter, shall respect a receiver retry-after value when it is later than the computed delay, and SHALL not start a retry before the persisted eligible time. Permanent validation, policy, digest, and authentication failures SHALL stop automatic retry.

#### Scenario: Offline retries respect the next eligible time
- **WHEN** the queue receives consecutive offline failures and a scheduler is invoked before then after the recorded next retry time
- **THEN** it starts no request before the time and exactly one eligible request after it

### Requirement: Configured transfer caps are globally enforced
The agent SHALL enforce the configured maximum simultaneous uploads and aggregate upload bandwidth across its queue. A work item that cannot obtain both capacity reservations SHALL remain queued without reading or sending archive bytes.

#### Scenario: Concurrent work never exceeds configured caps
- **WHEN** three ready archives are scheduled with a two-upload and one-chunk-per-tick bandwidth limit
- **THEN** the harness observes at most two active sessions and no more bytes per tick than the configured bandwidth limit

### Requirement: Users can control queued work without losing archives
The agent SHALL support explicit retry, pause, and cancel commands over durable queue state. Pause and cancel SHALL stop further requests while retaining the preserved archive and deterministic identity; explicit retry SHALL make a retryable entry eligible immediately without changing its identity.

#### Scenario: Paused work remains untouched
- **WHEN** a queued archive is paused and the scheduler runs
- **THEN** the harness receives no request for it and the local preserved archive remains available
