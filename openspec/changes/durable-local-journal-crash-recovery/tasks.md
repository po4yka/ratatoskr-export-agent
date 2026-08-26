# Tasks: durable-local-journal-crash-recovery

Each behaviour lands as a test-first pair. The test task declares the smallest
compile-safe shell required, runs it red, and records the behavioural failure
before its implementation task is marked complete.

## 1. Durable lifecycle and idempotency

- [x] 1.1 Add failing `LocalArchiveJournalTests`: `testEveryTransitionIsPersistedBeforeReturning`, `testIdempotencyKeyIsStableForTheSameDigest`, and `testDuplicateDigestCannotCreateSecondEntry`. Used a real temporary journal and a minimal throwing shell; `build-gate -- swift test --filter LocalArchiveJournalTests` failed with the expected `unavailable` shell error.
- [x] 1.2 Implement the strict lifecycle projection, write-ahead framed append/sync, digest-derived idempotency key, and duplicate-digest rejection. Verified focused tests green.

## 2. Crash replay and safe stop

- [x] 2.1 Add a failing crash-replay matrix in `JournalRecoveryTests`: inject a post-durability kill after each fixture transition (`discovered`, `archived`, `hashed`, `queued`, `uploading`, `uploaded`, `confirmed`), reopen the same file, and assert the consistent recovered state plus unchanged key. Added malformed, truncated, checksum-invalid, and impossible-transition fixtures asserting explicit safe-stop. Focused test was red: uploading remained uploading and corrupt records were not safe-stopped.
- [x] 2.2 Implement strict replay and launch recovery: retain valid states, durably return interrupted uploading entries to queued, and expose corruption as a safe-stop without modifying the journal. Verified the matrix green.

## 3. Bounded compaction and documentation

- [x] 3.1 Add failing `testCompactionReplaysTheSameProjectionWithinConfiguredBound` using enough transition history to cross a small configured journal ceiling; assert a reopen returns the same entries and the file is bounded. Focused test was red at 3,657 bytes against a 2,048-byte ceiling.
- [x] 3.2 Implement synchronized same-directory snapshot compaction and atomic replacement. Updated README status wording accurately. Verified the focused test green.

## 4. Full gate and ship

- [x] 4.1 Run `build-gate -- swift build`, `build-gate -- swift test`, `build-gate -- swift build -c release`, `.build/release/RatatoskrExportAgent --smoke`, `swiftlint`, `openspec validate --all --strict`, and `openspec validate --archived`. Observed: debug and release builds passed, smoke exited 0, 108 tests / 0 failures, SwiftLint 0 violations, strict validation 9/0, archived validation 2/0.
- [ ] 4.2 Commit the focused change on `feat/durable-local-journal-crash-recovery`, merge it into `main`, push `origin main`, and remove this worktree and branch only after the remote main contains the merge.
