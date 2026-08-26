## Context

`LocalArchiveStore` already preserves digest-addressed bytes atomically. The
next pipeline boundary needs a small durable local source of truth before any
upload client exists. The package has no third-party dependencies and the
development-status rules prohibit migration machinery.

## Goals / Non-Goals

Goals: durable write-ahead transitions; deterministic replay; a strict
corruption stop; digest-derived idempotency; bounded atomic compaction; and a
crash matrix using synthetic fixtures.

Non-goals: network requests, server operation polling, retries, credentials,
paths or archive content in the journal, provider parsing, or recovery by
discarding/repairing corrupted data.

## Decisions

### Framed append-only records

The journal is newline-delimited JSON. Each line is an envelope containing a
base64-encoded canonical payload plus a SHA-256 checksum of exactly those
payload bytes. The payload is either a transition or a complete compaction
snapshot. A transition is appended and `synchronize()`d before the in-memory
projection changes, so a returned transition is durable. A missing trailing
newline, bad JSON/base64/checksum, unknown record, duplicate sequence, invalid
state edge, or mismatched archive identity is corruption and recovery stops.

This avoids a database dependency while keeping failure modes inspectable. A
validly encoded but tampered record is detected by the checksum; semantic
validation protects against a valid but impossible sequence.

### State and recovery

Each entry has a local UUID, an `ArchiveFingerprint`, and a fixed idempotency
key `ratatoskr-export-agent/sha256/<lowercase digest>`. Only the documented
linear states are accepted. Replaying an `uploading` entry produces an
additional, durable recovery transition back to `queued` with the original key.
That state deliberately means “ask the future upload client to resolve the
uncertain server outcome with this key before sending bytes again.” Other
states stay unchanged. Duplicate digests are rejected when reserving a new
entry, preventing two queue items from sending the same archive.

### Compaction

When the journal is larger than its configured byte ceiling after a transition,
the complete projection is encoded as one snapshot in a same-directory
temporary file, synchronized, and atomically renamed over the journal. A crash
before rename leaves the old valid journal; after rename leaves the valid
snapshot. Compaction failure is reported and never loses a valid current log.

### Test seam

An injected post-durability hook throws a sentinel error at each transition;
each test closes the instance to simulate a process kill, reopens the fixture,
and checks replay. The test never relies on a fake journal writer: it exercises
the real append/sync/reopen path. Separate tests pin deterministic keys,
duplicate-digest rejection, compaction, and corruption safe-stop.

## Risks / Trade-offs

- `FileHandle.synchronize()` is macOS-specific but this package targets macOS.
- The snapshot holds only current entries, so historical audit detail is
  intentionally discarded at compaction; live recovery semantics are retained.
- Recovery refuses even a potentially recoverable truncated final record. This
  is deliberately conservative because silently guessing could double-send an
  archive.

## Migration Plan

The journal has one current schema encoded in its record payload. Fresh test or
local state is created from that definition; no migration or version-routing is
added. Rollback is code reversion while retaining the journal file untouched;
the operator can preserve it for diagnosis.
