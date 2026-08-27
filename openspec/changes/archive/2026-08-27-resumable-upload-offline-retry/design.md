## Context

See `proposal.md` for motivation and the delta specs for observable behavior. The existing local journal persists only lifecycle state and recovers `uploading` entries to `queued`; the menu exposes only Settings and Quit. The fleet blob-transfer specification defines digest-first session opening, server-issued opaque resumption tokens, indexed fixed-size chunks, status-led resumption, idempotent replay, and verified finalization. No authenticated Platform/receiver deployment is available to this repository yet.

## Goals / Non-Goals

**Goals:**

- Preserve one digest-derived remote identity across retries and process restarts.
- Resume only receiver-missing chunks after every uncertain transport outcome.
- Bound memory to one configured chunk, queue concurrency to one shared limiter, and bytes per second to one shared rate limiter.
- Drive worker and menu presentation from the same journal-derived queue projection.

**Non-Goals:**

- Changing fleet contracts, providing a receiving service, or claiming live endpoint integration.
- Provider login, cookie/session use, deep archive parsing, or deletion of a source/preserved archive.
- Background scheduling policy, backend operation/completeness projection, and notifications beyond generic local menu state.

## Decisions

### A transport protocol boundary owns canonical fixture encoding

Introduce `BlobReceiptTransport` with operations to open a digest-first session, obtain status, send one indexed chunk, and finalize. Its declaration is exactly the transport-honest fleet request shape; the digest-derived idempotency key remains separate from that wire object for the future authenticated edge binding. A test harness implements the boundary in process. Committed JSON fixtures copied from the fleet contract form the decoder/encoder oracle while the URLSession edge binding and integration remain pending.

This keeps the upload state machine testable and prevents test code from accidentally becoming a second transport dialect. A direct URLSession-only implementation was rejected because interruption sequences and cap assertions would depend on timing and a live service.

### The journal stores a non-secret upload checkpoint

Extend `JournalEntry` with an optional upload checkpoint: opaque resumption token, negotiated chunk size, received chunk indices (or an equivalent range form), attempt count, next eligible retry instant, and paused/cancelled state. The token is treated as a non-secret bearer-like protocol value for journal privacy purposes: it is never logged or rendered. A new write-ahead record snapshot persists updates before workers observe them.

This deliberately retains no credentials, user-controlled original source path, archive bytes, response body, or full remote error. It retains the agent-managed archive path locally so restart recovery can reopen the one preserved copy; that path is never transmitted, logged, or rendered. An external queue database was rejected because it would create two local sources of truth and recovery ordering ambiguity.

### An actor serializes the queue and shared capacity

`UploadQueue` is an actor backed by `LocalArchiveJournal`. It selects eligible entries, acquires one global upload slot and byte-rate reservation, performs one chunk through the protocol boundary, checkpoints the acknowledged state, and schedules the next eligible work. `UploadClock` and deterministic jitter are injected to make retry and rate tests free of wall-clock sleeps.

One actor with explicit reservations was chosen over a task-group-per-entry design because the latter cannot prove global caps once resumption and retry overlap. The queue deliberately serializes journal mutation while still allowing the configured number of transfer tasks to be active.

### All uncertain outcomes interrogate receipt status

On connection loss after open, chunk, or finalize, the queue retains its checkpoint and first queries session status. If the receiver says the session is complete, it verifies the stored receipt; if the token is unknown or expired, it opens using the same digest-derived idempotency key; otherwise it uploads only missing chunks. Receiver-declared retryability controls automatic retry; validation, policy, digest mismatch, and authentication outcomes stop it.

Blindly replaying the last request was rejected because it can duplicate finalization or conflict after a half-completed request.

### Menu progress is a projection, not a worker control path

`UploadQueueStatus` exposes redacted counts, active completed/total bytes, and generic transfer state. The AppKit menu creates a non-sensitive disabled status item from that projection and updates it on the main actor. Worker controls remain explicit queue commands rather than menu-side mutation.

This makes the status observable without surfacing names, paths, contents, credentials, tokens, full digests, or server errors.

## Risks / Trade-offs

- [Fleet HTTP binding or fixture shapes change before a receiver ships] → Pin fixture provenance in the repository and keep integration marked pending; update through a coordinated workspace change.
- [Token invalidation loses receipt-side progress] → Re-open with the same digest identity and let the receiver deduplicate; never treat an assumed chunk as acknowledged.
- [Per-chunk journal writes increase local I/O] → Persist only at acknowledged boundaries, compact through the existing journal mechanism, and retain correctness over throughput.
- [Bandwidth caps are approximate under URLSession buffering] → Reserve bytes before constructing each body and test observed chunk admission; do not claim wire-level QoS.
- [An opaque token could still be sensitive in some deployments] → Keep it out of logs/UI/diagnostics and scope journal file permissions; revisit its storage classification when the live contract is available.

## Migration Plan

1. Update the current version-1 configuration definition and every configuration fixture with new required transfer caps; no compatibility branch or migration is introduced.
2. Extend journal record coding in place and create test journals from the current definition; development status permits this schema replacement.
3. Ship the local queue disabled until a paired origin and a configured receiver binding exist; fixed-fixture tests establish local correctness only.
4. Before enabling a live endpoint, run the pending authenticated integration scenario against Platform edge and the receiving archive service. Rollback pauses the queue, leaves archives and journal records intact, and does not delete any local copy.
