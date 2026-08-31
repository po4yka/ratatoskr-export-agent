## ADDED Requirements

### Requirement: Onboarding and controls use the shared runtime
Settings SHALL provide HTTPS origin pairing, re-pairing, revocation, authorized folders, and user-controlled launch at login, while operational controls SHALL act on the shared runtime rather than independent state copies.

#### Scenario: Relaunch restores configured product state
- **WHEN** a paired user enables launch at login, authorizes a folder, and relaunches
- **THEN** settings restore non-secret identity and folder authority and the operational runtime resumes durable work

### Requirement: Smoke launch is offline
Smoke mode SHALL validate application bootstrap without pairing, opening a live session, starting upload work, or contacting Platform.

#### Scenario: Smoke performs no live calls
- **WHEN** the release executable runs with `--smoke`
- **THEN** the menu bootstrap succeeds and the process exits within its bound without a network request
