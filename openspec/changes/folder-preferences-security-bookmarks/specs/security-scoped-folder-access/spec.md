## Purpose

Owns the security-scoped bookmark lifecycle for user-chosen folders: creating scoped bookmarks at pick time, resolving them back to accessible URLs across restarts, relinquishing them on removal, and classifying resolution failures into actionable folder-access states.

## ADDED Requirements

### Requirement: Bookmark round trip restores the picked directory
Creating a bookmark for a picked directory SHALL produce data that resolves back to that same directory with readable access.

#### Scenario: Resolve returns the picked directory
- **WHEN** a bookmark is created for a picked directory and then resolved
- **THEN** resolution succeeds and yields a URL to that same directory whose contents are readable

### Requirement: Resolution survives process restart
A stored bookmark SHALL resolve on demand using only its persisted bytes, from a freshly created resolver instance, without requiring the original picking session.

#### Scenario: Fresh resolver resolves stored bytes
- **WHEN** a bookmark created in one resolver instance is handed as raw data to a newly created resolver instance
- **THEN** the fresh instance resolves it back to the same directory

### Requirement: Resolution failures map to actionable states
Resolution failures SHALL be classified into typed folder-access states: a stale or unparseable bookmark SHALL map to needs-reauthorization, a resolved-but-vanished target SHALL map to missing, and a permission failure SHALL map to denied. Each state carries an actionable meaning for display; failures are never swallowed into an undefined state.

#### Scenario: Stale bookmark maps to needs reauthorization
- **WHEN** resolution is attempted with bookmark bytes that no longer resolve to an existing folder
- **THEN** the resulting access state is needs-reauthorization

#### Scenario: Corrupt bookmark maps to needs reauthorization
- **WHEN** resolution is attempted with bytes that are not a valid bookmark
- **THEN** the resulting access state is needs-reauthorization

#### Scenario: Vanished folder maps to missing
- **WHEN** a resolvable bookmark's underlying directory is deleted after resolution succeeds once and access is then attempted again
- **THEN** the resulting access state is missing

#### Scenario: Permission failure maps to denied
- **WHEN** accessing a folder fails with a read-permission error
- **THEN** the resulting access state is denied

### Requirement: Broken access stays visible per folder
Every registered folder SHALL expose its current access state, and a folder whose bookmark cannot be resolved SHALL present needs-reauthorization rather than appearing healthy or disappearing from the registry.

#### Scenario: Unresolvable folder reports its broken state
- **WHEN** the access state of a folder whose stored bookmark cannot be resolved is queried
- **THEN** the reported state is needs-reauthorization and the folder remains listed in the registry

### Requirement: Resolved access is released on demand
Scoped access acquired during resolution SHALL be releasable, after which the resolver holds no open access for that folder until the next successful resolution.

#### Scenario: Release drops held access
- **WHEN** a resolved folder's scoped access is released and the release outcome is observed
- **THEN** the resolver reports no active access for that folder
