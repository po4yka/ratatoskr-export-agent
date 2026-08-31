## ADDED Requirements

### Requirement: Relaunch restores identity without persisting secrets
The agent SHALL persist only an HTTPS Platform origin and non-secret paired identity outside Keychain and SHALL keep device secret, access credential, and refresh token only in the non-synchronizing device Keychain record.

#### Scenario: Pair, relaunch, revoke, and re-pair
- **WHEN** a user pairs, relaunches, refreshes, revokes, and pairs again
- **THEN** identity and status survive appropriately while no credential appears in configuration, journal, logs, or visible state

### Requirement: Every authenticated request uses current session authority
Every prepare, transfer, status, finalize, and operation-poll request SHALL obtain current authority from the shared session coordinator, recover once from refusal, and stop in re-pairing-required state after revocation without deleting local work.

#### Scenario: Rotation and revocation affect later requests
- **WHEN** session rotation occurs and a later credential is revoked
- **THEN** later requests use the rotated credential and revocation stops work while preserving archive and queue state
