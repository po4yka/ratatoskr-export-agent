## MODIFIED Requirements

### Requirement: Update checking remains distribution-gated
With the manual-download distribution model selected, diagnostics SHALL report that update discovery is manual, include the current bundled short version when available, and MUST NOT contact an update endpoint, claim that an update exists, or request update-related permissions.

#### Scenario: User inspects update status after distribution selection
- **WHEN** diagnostics are assembled with a readable bundled short version
- **THEN** update status reports that updates are checked manually, includes the exact current version, and performs no network operation

#### Scenario: Bundled version cannot be read
- **WHEN** diagnostics are assembled without a readable bundled short version
- **THEN** update status reports manual checking with current version unavailable and performs no network operation

#### Scenario: User inspects update status during bootstrap
- **WHEN** diagnostics are assembled by an unbundled development or test process after the manual-download decision
- **THEN** update status reports manual checking with current version unavailable and no network operation is performed
