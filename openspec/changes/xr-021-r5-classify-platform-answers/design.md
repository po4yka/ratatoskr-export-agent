## Context

`retryCheckpoint(for:from:at:)` in `UploadQueue+Recovery.swift` already has branches for `BlobReceiptTransportError.retryAfter` and `.expiredSession`, but the Platform transport never raises them: `HTTPURLResponse.transportError` returns `.unavailable` for everything but 401, 403 and 413. Platform (R5-04 rule 5) answers 404 on `status`, `chunk` and `finalize` for a token that is expired, failed or dropped, and replaces a dead session on a repeated `open`.

## Decisions

### The classifier is a small value type that returns the error

`PlatformAnswerClassifier` holds the route, the status, the parsed envelope and the `Retry-After` seconds, and has one method that returns the error to throw. It lives in its own file so the transport file stays under the lint limits, and the table is testable through the real transport with `ResumableURLProtocol`. It returns `BlobReceiptTransportError.expiredSession` and `.retryAfter` (the layers allow it: both live in `AgentCore`), so no second expired-session error type exists.

### Precedence: route rows first, then the envelope, then the status class

R5-05 rule 1 says the envelope's `retryable` member decides when the body parses, and also lists statuses whose meaning depends on the route (404 on a transfer route means "reopen", 400 on `chunk` and `finalize` means "reconcile through status"). Platform's envelope for those statuses carries `retryable: false`, so letting the envelope decide would make the reopen and the reconcile unreachable. The order is therefore:

1. 401, 403 and 413 keep their current results (`PlatformAuthVerdict`, `refusedPermanently`, `payloadTooLarge`).
2. The explicit route rows: on `prepare` and `open`, 400, 422 and 409 are permanent and 404 is retryable; on `status`, `chunk` and `finalize`, 404 is `expiredSession`; on `chunk` and `finalize`, 400 is retryable.
3. Every other status: when the body parses as an `ErrorEnvelope` its `retryable` decides (so `retryable: true` rescues an unlisted 4xx and `retryable: false` on a 5xx is permanent); otherwise the status class decides (408, 429 and 5xx retryable, every other 4xx permanent).
4. A retryable result carries `Retry-After` (whole seconds) when the header is present, on every route.

A body parses as an envelope when it has a string `code` and a boolean `retryable`. A status outside 4xx and 5xx that reaches the mapping (a blocked redirect, an unexpected 2xx) stays `unavailable`, as today.

### Reopen state lives in the checkpoint

`expiredSession` already resets the checkpoint to "no token, no acknowledged chunks"; the change adds `sessionReopens` to it and compares the incremented value with `maxSessionReopens` (`AgentConfiguration`, default 3, copied into the queue). Past the bound the entry fails with `failureReason = sessionExpired`. The open key for reopen `n` is the journal key with the suffix `/session-n`; the journal identity key itself is unchanged, because `JournalIdentity.matches` pins it to the digest.

### Retry bound counts consecutive failures

`UploadRetryPolicy.maximumAttempts` (24) is compared with the incremented `attemptCount`; the 25th consecutive retryable failure fails the entry with `retriesExhausted`. The count is reset when the set of acknowledged chunks grows (a chunk the receiver took is proof of progress), not on a bare `status` answer, which would let a permanently failing `PUT` retry forever. A reopen keeps the existing increment and is bounded by `maxSessionReopens` instead. `capacityUnavailable` is a local admission decision and neither increments nor fails.

### A manual retry gives a fresh budget

`Retry Now` on a failed entry is offered by the menu. Without a reset it would fail again on the next retryable error. `controlRetry(.active)` therefore zeroes `attemptCount` and `sessionReopens` and clears `failureReason`.

### Reasons are projected by the existing menu rows

`ImportStatusMenuProjection` renders a queued entry whose upload failed as "Upload failed" and appends the reason ("retries exhausted", "session expired") when `failureReason` is set. No path, digest, token or key is shown.

## Risks

- A journal written before this change has no `sessionReopens` member and the decoder refuses it, so recovery stops safely. Accepted by the development status; the break is named in the commit body.
- Platform must really replace a dead session on a repeated `open` (R5-04 rule 5), or the reopen only repeats the 404. The agent cannot verify that here: no live Edge exists on this machine, and the Platform behaviour is covered by the Platform change.
