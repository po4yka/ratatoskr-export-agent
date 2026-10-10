## ADDED Requirements

### Requirement: Platform payload-too-large refusal is a permanent failure
When Platform answers an archive operation request with HTTP 413, the agent SHALL classify the failure as permanent, SHALL NOT schedule an automatic retry, and SHALL keep the preserved archive and report the entry as needing attention until the user explicitly retries it.

#### Scenario: Declared archive exceeds the Platform ceiling
- **WHEN** Platform answers the archive prepare request with 413 and a `payload_too_large` error envelope and the queue runs
- **THEN** the entry's upload checkpoint control is failed, no next retry time is scheduled, and the queue status counts it as needing attention

#### Scenario: Chunk upload is refused as too large
- **WHEN** Platform answers a chunk upload with 413 after the session opened and the queue runs
- **THEN** the entry's upload checkpoint control is failed, no next retry time is scheduled, and no further request is made on a later run
