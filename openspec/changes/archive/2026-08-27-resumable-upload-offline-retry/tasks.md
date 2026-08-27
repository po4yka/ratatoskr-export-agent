## 1. Contract fixtures and transfer configuration

- [x] 1.1 Add `Tests/AgentCoreTests/BlobTransferFixtureTests.swift::testMultiChunkSessionFixtureHasDigestFirstShape`, initially asserting the missing committed fixture decodes to a valid declaration; run it and confirm it fails because the fixture is absent.
- [x] 1.2 Add provenance-pinned fixed blob-transfer JSON fixtures under `Tests/AgentCoreTests/Fixtures/BlobTransfer/` and a fixture loader; rerun `testMultiChunkSessionFixtureHasDigestFirstShape` and confirm it passes without a live service.
- [x] 1.3 Add configuration tests in `Tests/AgentCoreTests/ConfigurationLoadingTests.swift` for accepted `uploadChunkBytes`/`maxUploadBytesPerSecond` and rejected zero/out-of-bound values; run them and confirm the valid document is rejected as unknown fields.
- [x] 1.4 Extend the current schema-version-1 `AgentConfiguration` and all configuration documents in place with validated, bounded transfer caps and documented defaults; rerun the configuration tests and confirm they pass.

## 2. Receipt protocol and durable checkpoints

- [x] 2.1 Add `Tests/AgentCoreTests/BlobReceiptTransportTests.swift::testOpenDeclarationPrecedesPayload` using an in-process recording harness and an injected transport boundary; run it and confirm it fails because no archive receipt client exists. The test-only harness setup cannot begin with a behavioral failure because the protocol boundary does not yet exist.
- [x] 2.2 Implement provider-neutral receipt request/response models and the `BlobReceiptTransport` boundary with fixture-compatible session opening; rerun `testOpenDeclarationPrecedesPayload` and confirm it passes with no payload request before opening.
- [x] 2.3 Add `Tests/AgentCoreTests/UploadJournalCheckpointTests.swift::testCheckpointSurvivesJournalReopenWithoutSecrets`, initially asserting an interrupted session checkpoint survives `LocalArchiveJournal.open`; run it and confirm it fails because no checkpoint is persisted.
- [x] 2.4 Extend the journal record and entry projection in place with a non-secret upload checkpoint and write-ahead checkpoint mutation; rerun `testCheckpointSurvivesJournalReopenWithoutSecrets` and confirm it passes while the serialized record contains no archive bytes, credentials, or full source path.
- [x] 2.5 Add `Tests/AgentCoreTests/BlobReceiptTransportTests.swift::testStoredReceiptMustMatchLocalFingerprint`, initially asserting a mismatched stored receipt is refused; run it and confirm it fails because receipt verification is absent.
- [x] 2.6 Implement stored-receipt size/digest verification and typed retryable versus permanent transfer failure classification; rerun `testStoredReceiptMustMatchLocalFingerprint` and confirm it passes.

## 3. Resumable idempotent upload

- [x] 3.1 Add `Tests/AgentCoreTests/ResumableUploadTests.swift::testResumesOnlyMissingChunksAfterBoundaryInterruption`, initially asserting the harness sees a status read followed only by missing indices after an acknowledged interruption; run it and confirm it fails because no upload worker resumes a session.
- [x] 3.2 Implement streaming fixed-size chunk transfer that checkpoints acknowledgements and resumes from receiver status; rerun `testResumesOnlyMissingChunksAfterBoundaryInterruption` and confirm it passes without replaying acknowledged chunks.
- [x] 3.3 Add `Tests/AgentCoreTests/ResumableUploadTests.swift::testRetryAfterLostFinalizeAcknowledgementCreatesOneReceipt`, initially asserting a retry for the same SHA-256 produces one final receipt; run it and confirm it fails because uncertain-finalize recovery is absent.
- [x] 3.4 Implement digest-derived session idempotency and status-first recovery for uncertain open/chunk/finalize outcomes; rerun `testRetryAfterLostFinalizeAcknowledgementCreatesOneReceipt` and confirm it passes with one receipt and the original identity.

## 4. Offline queue, retry timing, and caps

- [x] 4.1 Add `Tests/AgentCoreTests/OfflineUploadQueueTests.swift::testOfflineFailurePersistsAndDoesNotRetryBeforeEligibleTime`, using an injected clock and deterministic jitter; run it and confirm it fails because no durable scheduler exists.
- [x] 4.2 Implement the journal-backed `UploadQueue` actor with bounded exponential retry, retry-after handling, restart recovery, and permanent-failure stop behavior; rerun `testOfflineFailurePersistsAndDoesNotRetryBeforeEligibleTime` and confirm it passes without a wall-clock sleep.
- [x] 4.3 Add `Tests/AgentCoreTests/OfflineUploadQueueTests.swift::testGlobalConcurrencyAndBandwidthCapsAreEnforced`, initially asserting a recording harness never sees more than the configured active sessions or bytes per tick; run it and confirm it fails because capacity reservations are absent.
- [x] 4.4 Add one global queue slot limiter and byte-rate reservation before chunk body construction; rerun `testGlobalConcurrencyAndBandwidthCapsAreEnforced` and confirm it passes.
- [x] 4.5 Add `Tests/AgentCoreTests/OfflineUploadQueueTests.swift::testPauseCancelAndExplicitRetryPreserveArchiveIdentity`, initially asserting manual controls gate network work without deleting the preserved archive; run it and confirm it fails because control state is absent.
- [x] 4.6 Implement durable pause/cancel/explicit-retry queue commands and verify the test passes while the journal identity is unchanged.

## 5. Menu projection and full verification

- [x] 5.1 Add `Tests/RatatoskrExportAgentTests/UploadStatusMenuTests.swift::testMenuShowsRedactedQueuedAndProgressState`, initially asserting the menu observes a queue projection without filename/path/digest leakage; run it and confirm it fails because upload status is not presented.
- [x] 5.2 Add a main-actor menu projection bound to the queue status and rerun `testMenuShowsRedactedQueuedAndProgressState` to confirm it passes.
- [x] 5.3 Run `build-gate -- swift test`, `openspec validate --change resumable-upload-offline-retry --strict`, and `openspec validate --all --strict`; inspect the final diff and record that authenticated Platform/receiver integration remains pending because no live service is available.
