# local-operational-diagnostics Specification

## Purpose

Gives self-hosted users one privacy-safe view of local prerequisites and durable work health so common failures are actionable without engineering access.

## Requirements

### Requirement: Diagnostics assemble current local health
The diagnostics view SHALL assemble watched-folder access, notification authorization, available disk bytes, journal health, and upload queue depth from one explicit snapshot. Each category MUST distinguish healthy, degraded, and unavailable observations without inventing success.

#### Scenario: Mixed local state remains truthful
- **WHEN** one watched folder needs reauthorization, notifications are denied, disk capacity is readable, the journal is healthy, and uploads are queued
- **THEN** the assembled state exposes each observation separately with the exact degraded categories and queue count

#### Scenario: Journal cannot be read
- **WHEN** journal health cannot be established because recovery stopped safely on corruption
- **THEN** diagnostics report the journal as requiring attention and do not derive queue success from untrusted journal data

### Requirement: Diagnostics do not expose sensitive coordinates
The diagnostics state and panel MUST NOT contain watched-folder display names, filenames, full filesystem paths, archive content, credentials, configured endpoint URLs, backend private errors, full archive digests, or opaque upload tokens.

#### Scenario: Permission failure is rendered without a path
- **WHEN** access to a watched folder is denied
- **THEN** diagnostics show the denied folder count and recovery action without the folder's name or location

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

### Requirement: Diagnostics are user-accessible
The menu-bar agent SHALL expose a diagnostics panel that presents every diagnostic category and an action to export the support report.

#### Scenario: User opens diagnostics
- **WHEN** the user selects Diagnostics from the status menu
- **THEN** the panel shows permission, disk, journal, queue, and update-check state plus the support-report export action
