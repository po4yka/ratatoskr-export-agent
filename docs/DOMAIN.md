# Export Agent domain model

## Terms

- **Inbox scope:** user-approved directory and persistent security-scoped access.
- **Candidate file:** observed path not yet accepted as stable export.
- **Stable file:** size/metadata unchanged across checks and no temporary-download marker.
- **Fingerprint:** streaming SHA-256 plus size and shallow provider classification.
- **Local archive item:** immutable preserved original and metadata.
- **Journal entry:** durable state, attempts, operation ID, and safe error.
- **Upload session:** idempotent/resumable transfer to Platform.
- **Import/completeness status:** backend operation projection.
- **Backup age policy:** reminder threshold by provider.

## Lifecycle

`observed -> stabilizing -> fingerprinting -> archived -> queued -> uploading -> processing -> completed | failed | paused`

## Invariants

1. No provider credentials or browser sessions.
2. Accepted original is preserved before upload.
3. Journal state survives process termination.
4. Duplicate archive hash does not create duplicate backend import.
5. File content/filenames are absent from routine telemetry.
6. Backend provider service owns parsing/completeness authority.
