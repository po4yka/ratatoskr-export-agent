## ADDED Requirements

### Requirement: Trusted artifact is published as one immutable release
The owner-authorized workflow SHALL publish an explicit-version GitHub Release containing the final ZIP and SHA-256 only after exact source, Developer ID signature, notarization, stapling, and Gatekeeper checks succeed, using least required permissions and refusing tag or asset conflicts.

#### Scenario: Trust failure publishes nothing
- **WHEN** source, tag, signature, notarization, stapling, Gatekeeper, checksum, release, or asset validation fails
- **THEN** no GitHub Release or release asset is created or replaced

### Requirement: Clean-machine acceptance remains separate evidence
The repository SHALL provide a safe acceptance procedure for Gatekeeper, first launch, explicit folder authorization, pairing, Keychain restoration, interrupted resume, terminal status, manual updates, and rollback without bypassing platform trust.

#### Scenario: Local validation cannot claim external acceptance
- **WHEN** no owner-notarized artifact or separate compatible Mac is available
- **THEN** the procedure passes only its static safety contract and clean-machine acceptance remains externally blocked
