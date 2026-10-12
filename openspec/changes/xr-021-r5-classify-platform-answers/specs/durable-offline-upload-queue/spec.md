## ADDED Requirements

### Requirement: Platform answers are classified by route
The agent SHALL classify each Platform answer on the archive routes by route and status, and by the `retryable` member of the error envelope when no route rule applies. On `prepare` and `open`, HTTP 400, 422 and 409 SHALL be permanent failures and 404 SHALL be a retryable failure. On `status`, `chunk` and `finalize`, HTTP 404 SHALL mean the session is gone. On `chunk` and `finalize`, HTTP 400 SHALL be retryable. HTTP 408, 429 and 5xx SHALL be retryable on every route and SHALL honour `Retry-After`. Any other 4xx SHALL be permanent unless the envelope says `retryable: true`, and a 5xx whose envelope says `retryable: false` SHALL be permanent. HTTP 401, 403 and 413 keep their existing meaning.

#### Scenario: A malformed prepare is permanent
- **WHEN** Platform answers the prepare request with 400 and the queue runs
- **THEN** the entry's upload checkpoint control is failed with no next retry time

#### Scenario: A receiver that is not ready is retried
- **WHEN** Platform answers the prepare request with 404 and the queue runs
- **THEN** the entry stays active with the attempt count incremented and a next retry time

#### Scenario: Retry-After is honoured
- **WHEN** Platform answers a request with 429 and `Retry-After: 120` and the queue runs
- **THEN** the next retry time is at least 120 seconds after the run

#### Scenario: The envelope decides an unlisted status
- **WHEN** Platform answers with 418 and an envelope with `retryable: true`
- **THEN** the failure is retryable
- **WHEN** Platform answers with 503 and an envelope with `retryable: false`
- **THEN** the failure is permanent

### Requirement: A dead session is reopened
When Platform answers `status`, `chunk` or `finalize` with 404, the agent SHALL discard the stored resumption token and acknowledged chunks, and the next run SHALL open a new session for the same operation with a new idempotency key and resend the chunks. The number of reopens per entry SHALL be bounded by `maxSessionReopens` (default 3); the next expiry SHALL fail the entry with the reason `session_expired`.

#### Scenario: The token was dropped mid-upload
- **WHEN** Platform answers a chunk upload with 404 for a stored token and the queue runs again
- **THEN** the agent opens a session with an idempotency key different from the first open, receives a new token, resends the chunks and completes the upload

#### Scenario: The session keeps dying
- **WHEN** the fourth 404 on a transfer route occurs for one entry
- **THEN** the entry's upload checkpoint control is failed with the reason `session_expired`

### Requirement: Retries are bounded
`UploadRetryPolicy.maximumAttempts` (default 24) SHALL bound consecutive retryable failures of one entry. The next retryable failure SHALL fail the entry with the reason `retries_exhausted`. A capacity deferral SHALL NOT count, and an acknowledged chunk SHALL reset the count. A failed entry SHALL show its reason in the status menu, and a manual retry SHALL give the entry a fresh attempt and reopen budget.

#### Scenario: Retries run out
- **WHEN** the 25th consecutive retryable failure occurs
- **THEN** the entry's upload checkpoint control is failed with the reason `retries_exhausted` and no next retry time

#### Scenario: Progress resets the count
- **WHEN** each run acknowledges one more chunk before a retryable failure
- **THEN** the entry is still active after more than 24 failures in total
