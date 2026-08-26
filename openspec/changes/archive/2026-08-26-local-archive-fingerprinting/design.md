## Context

The watcher delivers `StableArchiveCandidate` values and stops there. This change adds the next pipeline stages - fingerprint, classify, preserve - as pure AgentCore types with no UI, network, journal, or Keychain surface. The package keeps its zero-dependency property: hashing uses CryptoKit (system framework), ZIP structure probing is a minimal hand-rolled central-directory reader over `Data`, JSON probing uses `JSONSerialization` on bounded prefixes. SwiftLint ceilings (`file_length` 183, `type_body_length` 128, `function_body_length` 35) shape the decomposition.

## Goals / Non-Goals

Goals: flat-memory hashing; advisory provider labelling; write-once content-addressed preservation; atomic publication under interruption; explicit budget refusal; every behaviour test-first against real temp directories.

Non-Goals: journal persistence (plan item 5), upload/queueing (item 7), deep parsing or completeness authority, deleting originals, provider login, cross-volume store placement guarantees beyond same-directory rename.

## Decisions

**Streaming hash via CryptoKit incremental SHA256 over 1 MiB chunks.** One-shot `SHA256.hash(data:)` loads whole files; the incremental hasher keeps memory flat. Chunk size 1 MiB balances syscall count and cache residency. Known-answer vectors (empty, `"abc"`, multi-chunk fixture) pin correctness without circular self-comparison. A size-shrunk-mid-hash failure surfaces as an error rather than a digest of partial bytes: read chunks while tracking remaining expected size, fail if the file ends early.

**Classifier = container sniff + marker table + confidence.** Magic bytes decide zip/json/unknown. Zip candidates are probed by parsing only the End-of-Central-Directory record from the last 64 KiB plus the central-directory entry names (names never contents), capped at 4096 names. Json candidates are probed by `JSONSerialization` over at most the first 64 KiB, inspecting root keys for objects or first-element keys for arrays. Provider rows are plain data:

| provider | required evidence |
|---|---|
| chatgpt | top-level `conversations.json` + `user.json` |
| claude | top-level `conversations.json` + `users.json` |
| instagram | any entry under `your_instagram_activity/` |
| threads | entry set defined by the table (`threads/` folder markers) |

All-required-for-one-row → strong; some-for-one-only → probable; overlapping partials across rows → ambiguous; none → unidentified. Rows are advisory routing hints to be refined against real exports later; the backend stays authoritative. Alternatives considered: third-party zip library (breaks zero-dependency property); filename-only detection (weaker than structure, kept out of this change).

**Store layout `<root>/<provider>/<yyyy>/<MM>/<digest>.<ext>`.** Matches README's documented layout; digest addressing makes paths collision-free by construction; extension preserved for user browsability only. Unknown/unidentified providers archive under an `unidentified` segment so nothing stable is ever refused for lacking a label.

**Single-pass copy+hash publish.** Archival streams source → temp file in the destination directory while updating the hasher; rename publishes atomically on the same volume. If the final path already exists: delete temp, compare existing bytes' digest (streamed) to the expected one - match returns the existing entry write-once, mismatch raises an integrity error. Alternative double-pass (hash then copy) was rejected: doubles I/O on multi-gigabyte exports for no added safety, since verification of copied bytes happens either way.

**Interruption seam for tests.** The archiver takes an injected `publishHook` closure invoked after each chunk flush and before rename; tests throw from it to simulate termination mid-move. Assertions check no final-path entry exists, then rerun without the hook succeeds. Real crash recovery of leftover `.tmp-*` files: stale temporaries carry the digest in their name and are swept by the next archival run before copying - cheap, idempotent, no daemon.

**Budget measured by walking the store once per archival.** Summing regular-file sizes under the store root before each publish is O(store) but simple, honest, and side-effect free; a persisted running total would need the journal (not built yet) to stay truthful across crashes. Refusal precedes any filesystem mutation. Configured via new `maxArchiveStoreBytes` on schema-v1 `AgentConfiguration`, decoded in place with default 20 GiB applied when absent - dev status allows in-place schema edits and forbids versioning machinery.

## Risks / Trade-offs

- [Central-directory reader mishandles exotic zips] → Bounded window plus strict signature checks degrade to unknown/probable labels, never misparse into wrong-provider claims; backend re-checks anyway.
- [Marker tables drift from real export shapes] → Tables are isolated data with unit pins; refining them is a one-file change, and unidentified outcomes still preserve safely.
- [Per-publish store walk grows costly on huge stores] → Acceptable pre-journal; revisit when the journal lands by carrying the total incrementally.
- [Rename atomicity assumed within one directory] → Temp files are always created inside the destination directory, so rename never crosses volumes.

## Migration Plan

Purely additive AgentCore surface plus one configuration field decoded in place; no data migration, no rollout ordering. Rollback is reverting the change; stores created by it are plain directories.

## Open Questions

None blocking. Exact Threads marker names may be revised when compared against real exports; the spec pins behaviour, not specific marker bytes.
