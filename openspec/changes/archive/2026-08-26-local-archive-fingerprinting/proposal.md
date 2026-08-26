## Why

Stable candidates currently stop at detection: nothing computes their identity, so the pipeline cannot deduplicate, preserve originals verifiably, or hand a provable digest to upload and journal stages. The monolith hashed uploads on receipt; hashing at the source makes integrity provable end to end, and preserving an immutable local copy before any network contact keeps the user's original safe regardless of what happens later.

## What Changes

- Add streaming SHA-256 fingerprinting: candidate bytes are hashed in bounded chunks from the source file, never loaded whole into memory; the digest and byte size become the archive's local identity.
- Add shallow classification: container sniffing by magic bytes (ZIP, JSON) plus bounded structural probes - ZIP central-directory entry names and top-level JSON keys only - label candidates as ChatGPT, Claude, Instagram, Threads, or unidentified export candidates with a confidence level and recorded evidence. Classification stays advisory routing metadata; no entry contents are decompressed or parsed and the backend remains the parsing authority.
- Add the immutable local archive store: preserved copies move into an agent-managed store laid out by provider and calendar month, content-addressed by digest with write-once semantics; an already-preserved digest is recognized and never rewritten, and differing content can never replace existing store content.
- Make every store file operation atomic: content reaches its final path only through a temporary file in the destination directory followed by one rename, so no partial state is ever visible at a final path and an interruption leaves either the previous state or a recoverable temporary behind.
- Enforce a disk budget for the store: a configured maximum total byte size refuses archival up front, before copying begins, with an explicit over-budget outcome rather than a mid-copy failure.
- Extend the version-1 configuration document in place with the archive-store budget field `maxArchiveStoreBytes`, defaulted when absent and validated positive like the other budgets.

## Capabilities

### New Capabilities

- `streaming-fingerprinting`: computing a stable candidate's SHA-256 digest and size by bounded chunked reads, with correctness independent of how writes were chunked and known-answer vectors pinning the algorithm.
- `shallow-archive-classification`: labelling an archive candidate's container type and probable provider from magic bytes and shallow structure probes, including ambiguity and unidentified outcomes, without extracting or deeply parsing content.
- `immutable-local-archive-store`: the agent-owned preservation store - digest-addressed layout, write-once publication through atomic temp-plus-rename, verified copied bytes, duplicate recognition, simulated-interruption safety, and explicit refusal when the configured disk budget would be exceeded.

### Modified Capabilities

- `typed-configuration`: the version-1 configuration document gains `maxArchiveStoreBytes` with a documented default applied when absent, rejected values at zero or below, and unchanged strict unknown-field rejection.

## Impact

- New types in the `AgentCore` target: a streaming hasher, the shallow classifier with its marker tables, and the content-addressed archiver actor plus its result and error types. Existing watcher types keep their public interfaces; the archiver consumes `StableArchiveCandidate`.
- `AgentConfiguration` gains one field decoded in place under schema version 1; defaults and validation tests extend accordingly.
- Tests grow in `AgentCoreTests`: synthetic ZIP and JSON fixtures built inside the test run, known-answer hash vectors, injected failure points simulating termination mid-publish, and real temporary directories as stores. No personal exports enter the repository.
- No UI, network, Keychain, or journal surface changes; upload, journal, and reminders remain future work. Nothing here logs paths, filenames, or digests beyond redacted prefixes.
