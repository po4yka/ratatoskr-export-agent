## 1. Classification table (XR-021 CONTRACTS.md R5-05 rule 1)

- [x] 1.1 Add `Tests/AgentCoreTests/PlatformArchiveStatusClassificationTests.swift` using the `ResumableURLProtocol` harness, one row per route and status of the table: permanent (`control == .failed`, no `nextRetryAt`) for 400, 422 and 409 on prepare and open, for an unlisted 418 and for 503 with `retryable: false`; retryable (attempt incremented, `nextRetryAt` set) for 404 on prepare and open, for 408, 429 and 503 on every route, for 400 on chunk and finalize, and for 418 with `retryable: true`; `Retry-After: 120` pushes `nextRetryAt` at least 120 s out; 404 on status, chunk and finalize discards the token; 401 (Platform verdict), 403 and 413 keep today's results. Run it and confirm it fails because every row but 401, 403 and 413 is `unavailable`.
- [x] 1.2 Add `PlatformAnswerClassifier` and the route to `transportError`; raise `BlobReceiptTransportError.expiredSession` and `.retryAfter` from it. Rerun and confirm all rows pass.

## 2. Reopen (R5-05 rule 2)

- [x] 2.1 In the new `PlatformArchiveSessionReopenTests` (`PlatformResumableArchiveHTTPTransportTests.swift` is already at the file-length limit) add a test where a 404 on `chunk` with a stored token is followed by a second run that opens a new session with a different `Idempotency-Key`, receives a new token, resends the chunks and completes; and a test where the fourth 404 fails the entry with the reason `session_expired`; and a test that `Retry Now` on a failed entry restores its budget. Add `sessionReopens`, `failureReason` and `AgentConfiguration.maxSessionReopens` as neutral members first. Run and confirm the failures are the repeated idempotency key and the missing bound.
- [x] 2.2 Bound the reopens in `retryCheckpoint`, derive a fresh open key per reopen, persist `sessionReopens` through every checkpoint rewrite, and reset the budget on a manual retry. Rerun and confirm the tests pass.

## 3. Bounded retries (R5-05 rule 3)

- [ ] 3.1 Add `UploadRetryPolicy` tests (`maximumAttempts` defaults to 24), queue tests (the 25th consecutive retryable failure fails with `retries_exhausted`; `capacityUnavailable` does not count; an acknowledged chunk resets the count) and extend `ImportStatusMenuTests` for the failed row with its reason. Add `maximumAttempts` as a neutral member first. Run and confirm the entry stays active after the 25th failure and the row shows no reason.
- [ ] 3.2 Enforce the bound in `retryCheckpoint`, reset the count on chunk progress, and project the reason in `ImportStatusMenuProjection`. Rerun and confirm the tests pass.

## 4. Documentation

- [ ] 4.1 State the table, the reopen rule and the bounds in `README.md` and `docs/ARCHITECTURE.md`, and replace the nonexistent `imports`, `upload-session` and `complete-upload` paths in section 22 with the real Platform routes. Documentation cannot start from a failing test.

## 5. Gate

- [ ] 5.1 Run `swift build`, `swift test`, `swift build -c release`, the release `--smoke` launch, `Tests/Distribution/run.sh`, `swiftlint`, and `openspec validate --all --strict`; all pass. A gate run is not a behaviour and cannot start from a failing test. No live Edge exists on this machine, so no end-to-end run is claimed.
