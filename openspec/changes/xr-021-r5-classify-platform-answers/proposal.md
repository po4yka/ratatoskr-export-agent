## Why

`PlatformArchiveHTTPTransport` maps every status other than 401, 403 and 413 to `unavailable`, and `UploadQueue` reschedules `unavailable` forever with an hourly cap (XR-021 CONTRACTS.md section R5-05). Two defects follow. A resumption token that Edge expired (24 h), failed or dropped answers 404 on `status`, `chunk` and `finalize`; the agent keeps polling that dead token and never reopens a session, so a laptop that was offline for more than a day wedges the entry. And a condition that can never succeed (a malformed prepare, an idempotency conflict, an unlisted 4xx) is retried with no limit.

## What Changes

- A `PlatformAnswerClassifier` maps (route, status, parsed `ErrorEnvelope`, `Retry-After`) to the transport error, per the R5-05 table; `HTTPURLResponse.transportError` takes the route.
- A 404 on `status`, `chunk` or `finalize` raises `BlobReceiptTransportError.expiredSession`. The queue clears the stored token and acknowledged chunks, and the next run calls `openTransfer` with a fresh `Idempotency-Key` for the same operation.
- `UploadCheckpoint` gains `sessionReopens` and `failureReason`. `AgentConfiguration.maxSessionReopens` (default 3) bounds the reopens per entry; the fourth expiry fails the entry with the reason `session_expired`.
- `UploadRetryPolicy.maximumAttempts` (default 24) bounds consecutive retryable failures; the 25th fails the entry with the reason `retries_exhausted`. `capacityUnavailable` does not count; an acknowledged chunk resets the count.
- The menu projection of a failed entry shows the reason. A user "Retry Now" on a failed entry gives it a fresh attempt and reopen budget.
- `README.md` and `docs/ARCHITECTURE.md` state the table, the reopen rule and the bounds, and section 22 lists the real Platform routes.
- **Deliberate break:** `UploadCheckpoint` has two new required journal fields. There is no shim for journals written before this change (development status).
- **Deliberate break:** 4xx answers that were retried forever as `unavailable` are now permanent (400, 422 and 409 on prepare and open; any unlisted 4xx), and a retryable failure past 24 consecutive attempts now fails the entry.

## Capabilities

### Modified Capabilities

- `durable-offline-upload-queue`: Platform answers are classified by route; a dead session is reopened; retries are bounded.

## Impact

- Affects `AgentCore` (`URLSessionPlatformArchiveOperationTransport`, the new classifier, `UploadCheckpoint`, `UploadQueue` recovery and scheduling, `UploadRetryPolicy`, `AgentConfiguration`, `ImportStatusMenuProjection`), the status menu tests, `README.md` and `docs/ARCHITECTURE.md`.
- Cites XR-021 CONTRACTS.md section R5-05 (and R5-04 rule 5 for the Platform behaviour this depends on). No contracts pin, no wire shape change. The Swift agent cannot be run against a live Edge on this machine; every test uses the in-process `ResumableURLProtocol` harness or hand-written fakes.
- Out of scope: the fixed 1 MiB chunk ceiling, the macOS 14 `.iso8601` floor, per-request `URLSession` leaks, a probe at prepare for an unmapped user, Platform and the importers.
