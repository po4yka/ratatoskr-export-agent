## ADDED Requirements

### Requirement: Only Platform's own 401 costs the device pairing
The agent SHALL treat a `401` as a rejected device credential only when its body is an error envelope with code `platform.auth.unauthenticated`. Any other `401`, including one with an empty or malformed body, SHALL be reported as unavailable and SHALL NOT remove the stored credential or change the pairing status.

#### Scenario: A receiver's 401 relayed at finalize
- **WHEN** both the first and the refreshed request are answered `401` with code `claude.auth.unauthenticated`
- **THEN** the stored credential is still present, the pairing status stays paired, and the call fails as unavailable

#### Scenario: A 401 without an envelope
- **WHEN** both requests are answered `401` with an empty body, or with a body that is not an error envelope
- **THEN** the stored credential is still present and the pairing status stays paired

#### Scenario: Platform's own verdict
- **WHEN** both requests are answered `401` with code `platform.auth.unauthenticated`
- **THEN** after exactly one refresh the credential is removed and re-pairing is required

### Requirement: A Platform 403 on the archive routes is a permanent failure
When Platform answers an archive operation request with HTTP 403, the agent SHALL classify the failure as permanent, SHALL NOT schedule an automatic retry, and SHALL keep the preserved archive and report the entry as needing attention until the user explicitly retries it.

#### Scenario: Finalize is refused
- **WHEN** Platform answers the finalize request with 403 and code `chatgpt.account.unmapped` and the queue runs
- **THEN** the entry's upload checkpoint control is failed, no next retry time is scheduled, the menu title reads "1 upload need attention", and no further request is made on a later run

#### Scenario: Prepare is refused
- **WHEN** Platform answers the prepare request with 403 and the queue runs
- **THEN** the entry's upload checkpoint control is failed with no next retry time
