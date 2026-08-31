## ADDED Requirements

### Requirement: Manual update destination is the accepted release
The explicit update action SHALL open the project's HTTPS Releases destination, where the accepted immutable artifact and checksum are published, and SHALL not download or install code automatically.

#### Scenario: User explicitly checks for an update
- **WHEN** the user selects Check for Updates
- **THEN** the application opens the fixed HTTPS Releases destination without an automatic download or installation
