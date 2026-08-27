# upload-progress-menu-status Specification

## Purpose
Makes queue and upload progress transparent in the menu bar without leaking archive paths, names, contents, credentials, or full content digests.

## Requirements

### Requirement: Menu status reflects the persisted queue projection
The menu-bar status surface SHALL display active upload progress, queued count, and paused/offline retry state from the same persisted queue projection used by the worker. It SHALL update when a durable queue state changes.

#### Scenario: Interrupted upload is shown as queued for retry
- **WHEN** an upload becomes queued after an interrupted chunk request
- **THEN** the menu status reports a queued retry state and does not report upload completion

### Requirement: Menu status is privacy preserving
Menu-bar status SHALL use counts, percentages, generic transfer state, and at most a short local identifier. It SHALL NOT show archive filenames, filesystem paths, archive contents, credentials, full digests, or backend private errors.

#### Scenario: Upload progress omits sensitive source metadata
- **WHEN** an archive with a sensitive filename is uploading
- **THEN** its menu status exposes progress and generic state without any portion of that filename or its full digest
