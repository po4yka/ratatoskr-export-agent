## Why

Self-hosted users can currently see import and upload status, but they cannot tell from the app when watched work has stalled or collect a safe support snapshot without engineering help. Operational diagnostics and privacy-by-construction support export are needed before distribution decisions can be made safely.

## What Changes

- Add bounded, non-nagging reminders when a watched folder has unprocessed items older than a configurable threshold.
- Add a diagnostics surface that assembles watched-folder access, notification authorization, available disk space, journal health, and upload queue depth into actionable local state.
- Add an exportable support report whose default schema admits only bounded counters, enums, timestamps, and shortened digests; filenames, bounded text detail, or URLs can enter only through an explicit field selection for one reviewed item, while filesystem paths and credentials remain prohibited.
- Represent update checking as unavailable pending the item 10 distribution decision; no update endpoint, network request, or distribution assumption is introduced.

## Capabilities

### New Capabilities

- `watched-item-reminders`: Threshold evaluation, suppression, and privacy-safe delivery for watched items that remain unprocessed.
- `local-operational-diagnostics`: Assembly and presentation of permission, disk, journal, queue, and deferred update-check state.
- `redacted-support-report`: Construction and export of a bounded diagnostic report that cannot include sensitive fields by default.

### Modified Capabilities

- `terminal-import-notifications`: Extend the shared notification boundary to deliver privacy-safe watched-item reminders without changing terminal import semantics.

## Impact

- Affects `AgentCore` operational projections and notification boundaries, the macOS settings/diagnostics UI, and XCTest coverage.
- Reads only already-authorized watched-folder state, local filesystem capacity, local journal projection/health, queue status, and notification authorization.
- Adds no production dependency, backend contract, provider parsing, credential handling, telemetry upload, update service, or distribution entitlement.
