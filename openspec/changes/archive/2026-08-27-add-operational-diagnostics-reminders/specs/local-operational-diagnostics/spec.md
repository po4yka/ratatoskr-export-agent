## Purpose

Gives self-hosted users one privacy-safe view of local prerequisites and durable work health so common failures are actionable without engineering access.

## ADDED Requirements

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
Until the distribution model is selected, diagnostics SHALL represent update checking as deferred and MUST NOT contact an update endpoint, invent update availability, or request update-related permissions.

#### Scenario: User inspects update status during bootstrap
- **WHEN** diagnostics are assembled before the item 10 distribution decision
- **THEN** update status is reported as deferred pending distribution selection and no network operation is performed

### Requirement: Diagnostics are user-accessible
The menu-bar agent SHALL expose a diagnostics panel that presents every diagnostic category and an action to export the support report.

#### Scenario: User opens diagnostics
- **WHEN** the user selects Diagnostics from the status menu
- **THEN** the panel shows permission, disk, journal, queue, and update-check state plus the support-report export action
