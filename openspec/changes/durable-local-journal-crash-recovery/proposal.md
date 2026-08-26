## Why

The watcher, fingerprinter, and immutable archive store now survive individual
filesystem interruptions, but the agent has no durable record linking a
preserved digest to the next upload action. A process crash can therefore lose
work or leave an in-progress upload ambiguous. This change implements plan item
5 with an append-only local write-ahead journal whose recovery path never
guesses after corruption.

## What Changes

- Add an AgentCore local journal that durably records every lifecycle
  transition: discovered, archived, hashed, queued, uploading, uploaded, and
  confirmed.
- Derive a stable upload idempotency key from the archive SHA-256 digest, and
  retain it across replay and interrupted uploads.
- Replay valid journal records on launch into a deterministic projection;
  interrupted `uploading` work returns to `queued` with the same key, while
  terminal and pre-upload states remain intact.
- Detect malformed, truncated, checksum-invalid, or semantically inconsistent
  journals as an explicit safe-stop. Recovery neither overwrites the journal
  nor invents entries.
- Compact long journals atomically into a verified snapshot so disk use is
  bounded without losing the live projection.

## Capabilities

### New Capabilities

- `durable-local-journal`: append-only write-ahead state transitions, strict
  replay and corruption safe-stop, deterministic digest-derived idempotency,
  and atomic bounded compaction for locally preserved archive work.

## Impact

- New Foundation/CryptoKit-only `AgentCore` types and synthetic-fixture tests;
  no UI, network, Platform, Keychain, provider parsing, or deletion behaviour
  is introduced.
- This implements existing local idempotency semantics from repository docs;
  it does not change the Platform upload contract. The later uploader will use
  the persisted key and must query the server before retrying uncertain work.
- README status wording changes to distinguish a local crash-safe queue from
  the still-unimplemented network uploader.
