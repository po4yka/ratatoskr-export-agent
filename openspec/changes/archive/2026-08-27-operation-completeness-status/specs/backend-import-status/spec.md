## Purpose

Tracks the backend's imported-archive operation as durable local state so each archive has a
truthful, privacy-safe status even when the backend cannot currently be reached.

## ADDED Requirements

### Requirement: Archive status is projected only from local or backend evidence
The agent SHALL present `archived`, `uploading`, `processing`, `imported-complete`,
`imported-with-gaps`, or `failed` from its durable archive state and valid Platform operation
payloads. Only an `ai_archive.import` result containing the workspace-defined valid summary with
`completeness` `complete` SHALL produce `imported-complete`; every other valid completeness class
SHALL produce `imported-with-gaps`. A terminal operation without a valid summary SHALL be marked
unverified and SHALL not be presented as a completed import.

#### Scenario: Complete fixture maps to imported-complete
- **WHEN** a stored archive operation response contains a valid complete import summary
- **THEN** its local presentation is `imported-complete` with the backend observation timestamp

#### Scenario: Partial fixture maps to imported-with-gaps
- **WHEN** a stored archive operation response contains a valid non-complete import summary
- **THEN** its local presentation is `imported-with-gaps` and retains the reported gap count

#### Scenario: Failed operation maps to failed
- **WHEN** the Platform operation response has terminal status `failed` or `cancelled`
- **THEN** its local presentation is `failed` without exposing the backend error text

### Requirement: Unreachable polling retains last known truth
The agent SHALL persist the last valid backend observation, including operation id and observation
time. When a poll is unreachable or invalid, it SHALL retain that projection and render its
last-known timestamp; it SHALL NOT manufacture a newer processing, complete, partial, or failed
state.

#### Scenario: Poll fails after processing was observed
- **WHEN** a durable processing observation exists and the next operation poll is unreachable
- **THEN** the UI retains processing and identifies the stored observation time as last known

### Requirement: Terminal notices are permission-gated and private
The agent SHALL notify only when a newly observed terminal import presentation has not already been
notified and local notification permission is authorized. The notice SHALL be generic and SHALL NOT
include archive filenames, paths, content, full hashes, credentials, backend error text, or counts.

#### Scenario: Denied permission suppresses a completed-import notice
- **WHEN** a new terminal imported-complete observation is recorded while notification permission
  is denied
- **THEN** the agent stores the observation but does not deliver a notification

#### Scenario: Authorized terminal import produces one generic notice
- **WHEN** a newly observed imported-with-gaps terminal result is recorded while permission is
  authorized
- **THEN** the agent delivers one generic attention notice and does not repeat it for the same
  terminal observation
