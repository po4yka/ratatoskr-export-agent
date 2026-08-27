# Ratatoskr Export Agent

`ratatoskr-export-agent` is the local macOS companion for importing official ChatGPT and Claude data exports into Ratatoskr. It watches a user-controlled inbox, identifies provider archives, verifies and submits them to the local Ratatoskr deployment, preserves the original files, and reports backup freshness and import completeness.

> **Status:** bootstrap core delivered as a SwiftPM package: typed configuration loading, privacy-redacting logging, a menu-bar agent shell with a headless `--smoke` mode, watched-folder preferences backed by security-scoped bookmarks (Settings window with per-folder enable and archive-policy controls and actionable access-failure states), enforced size limits, an FSEvents-backed inbox watcher with debounced scans over enabled folders, completed/stable-file detection (quiet-period evidence, writer-hold probe where detectable, temporary-suffix exclusion, regular-file/size/readability gates) emitting stable candidates, streaming SHA-256 fingerprinting over bounded chunk reads, shallow archive classification (magic-byte container sniffing plus bounded central-directory/top-level-key probes labelling ChatGPT/Claude/Instagram/Threads candidates with confidence evidence), an immutable content-addressed local archive store with atomic temp-plus-rename publication, write-once duplicate recognition, a configurable disk budget with explicit over-budget refusal, and a bounded write-ahead local journal. The journal records durable transitions, replays interrupted uploads back to the same idempotency-keyed queue entry, and fails closed on corruption. Platform device pairing, rotating session credentials, macOS Keychain storage, durable authenticated operation polling, privacy-safe per-archive menu status, and permission-gated generic terminal notices are implemented. Network archive upload, reminders, background lifecycle wiring, LaunchAgent packaging, and signing remain pending.

> [!IMPORTANT]
> **Ratatoskr is in development.** No database holds data that has to survive a schema change.
> While this status holds, these two rules replace what the documents below plan:
>
> - the API and the database keep their first version. There is no `v2` and no later major
>   version.
> - the database has no migrations. One schema definition exists, and a schema change edits it in
>   place.
>
> Only the repository owner changes this status.

## Why a local agent is required

Personal ChatGPT and Claude accounts provide user-initiated data exports rather than a stable API for continuously listing every consumer chat and project. Ratatoskr therefore uses periodic official export snapshots.

The Export Agent removes the repetitive local steps after the user downloads an archive:

```text
Provider export email
  -> user downloads ZIP
  -> Ratatoskr Inbox
  -> Export Agent detects and hashes it
  -> local Ratatoskr upload
  -> provider archive service imports it
  -> completeness report
  -> original ZIP retained locally
```

It does not automate provider login, request passwords, capture browser cookies, bypass MFA, or call undocumented consumer endpoints.

## Core responsibilities

- monitor one or more user-selected inbox directories;
- detect likely ChatGPT and Claude exports;
- calculate archive SHA-256 before submission;
- avoid duplicate uploads;
- perform lightweight local safety and size checks;
- upload to the configured local Ratatoskr Edge API;
- track operation progress and import result;
- move or copy accepted archives into an immutable local archive layout;
- show completeness reports and actionable warnings;
- report the age of the latest successful backup per provider/account;
- create configurable reminders to request new exports;
- notify when a downloaded export has not yet been imported;
- operate without provider passwords, cookies, or long-lived browser credentials.

## Proposed components

The repository is expected to contain a native macOS application and a narrowly scoped background component:

```text
ratatoskr-export-agent/
├── App/
│   ├── SwiftUI interface
│   ├── account and endpoint settings
│   ├── inbox management
│   ├── import history
│   └── completeness reports
├── Agent/
│   ├── filesystem observation
│   ├── archive fingerprinting
│   ├── upload queue
│   ├── retry policy
│   └── notifications
├── Shared/
│   ├── models
│   ├── Ratatoskr API client
│   ├── Keychain access
│   └── diagnostics
└── Tests/
```

The final process topology may use one app with a login item, a LaunchAgent, or an XPC helper. The least privileged reliable design should be selected during implementation.

## Inbox model

The user explicitly chooses a directory such as:

```text
~/Downloads/Ratatoskr Inbox/
```

The agent observes new regular files and waits for the download to become stable before processing. It never recursively scans the entire home directory by default.

A local archive layout may use:

```text
~/Documents/Ratatoskr Exports/
├── chatgpt/
│   └── 2026/08/<sha256>.zip
└── claude/
    └── 2026/08/<sha256>.zip
```

The exact original bytes are preserved. Renaming or organization metadata is stored separately and never changes the calculated hash.

## Detection and routing

Detection is evidence-based and conservative. Signals may include:

- archive filename patterns;
- top-level archive entries;
- provider-specific manifest or JSON structure;
- safe, bounded content inspection;
- explicit user override when detection is uncertain.

The agent does not fully parse conversations or projects. It identifies the provider and routes the immutable archive to:

```text
ratatoskr-chatgpt
ratatoskr-claude
```

Provider services own schema detection, safe extraction, normalized import, completeness, and replay.

## Local processing flow

```text
observed
  -> waiting_for_stable_file
  -> fingerprinting
  -> duplicate_check
  -> ready_to_upload
  -> uploading
  -> operation_running
  -> imported
  -> archived_locally
```

Failure states remain recoverable:

```text
unsupported
unsafe_or_too_large
upload_failed
server_rejected
import_partial
import_failed
archive_move_failed
```

The agent stores a local journal so restarts do not duplicate work or lose the relationship between a file, upload operation, and final import report.

## Ratatoskr API interaction

The agent communicates only with `ratatoskr-platform` through the public local API.

A planned flow:

1. authenticate as a registered local device;
2. create an AI-archive import operation with an idempotency key;
3. stream or upload the file using a bounded request;
4. verify the server-reported SHA-256 matches the local hash;
5. follow operation progress;
6. retrieve the resulting provider export and completeness report;
7. mark the local journal entry complete.

The agent never writes directly to ChatGPT/Claude database schemas or BlobStore paths.

## Duplicate handling

The archive hash is the primary duplicate identity. Before upload, the agent asks Ratatoskr whether the content hash is already present.

Outcomes:

- **new archive:** upload and import;
- **already imported:** link the local file to the existing snapshot and skip upload;
- **previous import failed:** offer retry against the same immutable archive;
- **same filename, different hash:** treat as a distinct export;
- **same hash, different provider selection:** stop and require manual review.

No provider archive is deleted merely because it is a duplicate.

## Reminders and freshness

The agent may track:

```text
last_export_requested_at
last_archive_downloaded_at
last_archive_imported_at
last_complete_or_accepted_snapshot_at
latest_snapshot_completeness
```

User-configurable policies may notify:

- monthly or weekly when no new export has been imported;
- before an expected provider download link expires, when such a signal is explicitly available;
- when a file is waiting in the inbox;
- when an import is partial or missing assets;
- when the local Ratatoskr endpoint has been unreachable;
- when the local archive and server snapshot hashes disagree.

The agent does not claim background access to a provider email account unless a separate, explicit mail integration is configured outside this repository.

## Local state and secrets

Local state may include:

```text
configured Ratatoskr endpoints
registered device identity
security-scoped directory bookmarks
file journal
archive hashes
operation IDs
notification preferences
backup freshness projections
```

Secrets and tokens are stored in macOS Keychain. Logs never include:

- Ratatoskr bearer tokens;
- archive contents;
- conversation titles or messages;
- provider download links;
- user filesystem paths beyond redacted diagnostics.

## Filesystem and sandbox security

1. The user selects every watched directory explicitly.
2. The agent processes regular files only and rejects unsafe symlink/path transitions.
3. It does not extract provider archives locally beyond bounded detection.
4. Files remain unchanged while hashing and upload are in progress.
5. Archive moves are atomic where the filesystem permits.
6. A failed upload never deletes the source file.
7. Security-scoped bookmarks are minimized and revocable.
8. Temporary copies are confined and cleaned after verified completion.
9. Local archives are never exposed through an unauthenticated web server.

## Privacy model

The agent is designed for a local, user-controlled Ratatoskr deployment. It should make the destination explicit before every first upload and expose:

- server identity and TLS status;
- account/device registration;
- archive hash and size;
- provider classification;
- operation status;
- local and server retention status.

No telemetry containing archive names or personal content is sent to third parties by default.

## Observability and diagnostics

User-visible diagnostics include:

```text
inbox watcher status
last scan time
queued files
upload progress
operation progress
last successful import
snapshot age
completeness status
retry reason
endpoint reachability
```

Technical metrics/logs remain local and bounded. A diagnostic bundle must redact paths, tokens, archive filenames where sensitive, and all content.

## Non-goals

- Requesting or downloading provider exports without explicit user action.
- Logging into ChatGPT or Claude.
- Storing passwords, cookies, MFA secrets, or undocumented session tokens.
- Parsing and normalizing provider conversations locally.
- Acting as the authoritative archive database.
- Deleting provider ZIP files automatically after upload.
- Searching or analysing conversations.
- Watching the entire filesystem by default.

## Initial milestones

1. Create the native macOS app shell and typed local journal.
2. Add explicit inbox selection and stable-file observation.
3. Implement SHA-256 fingerprinting and duplicate checks.
4. Add registered-device authentication and Ratatoskr API client.
5. Upload archives with idempotency and progress.
6. Display provider import and completeness results.
7. Add safe local archival and retry semantics.
8. Add backup-age reminders and notifications.
9. Add hardened sandbox, Keychain, and diagnostic behavior.
10. Validate real ChatGPT and Claude export workflows end to end.

## Workspace integration

The planned workspace harness will pin the Export Agent with compatible Platform, ChatGPT, Claude,
and AI-archive contract commits. That pin and the product CI do not exist yet. Future public CI will
use synthetic archives; real personal exports remain outside the repository and protected test
infrastructure.

## Project status

This README defines the intended macOS export-ingestion companion. The package scaffold, typed configuration, redacting logger, menu-bar shell with smoke mode, watched-folder preferences with security-scoped bookmarks and a settings window, the inbox watcher over enabled folders, completed/stable-file detection, streaming SHA-256 fingerprinting, shallow provider classification, and the immutable content-addressed local archive store with atomic publication and disk budget exist today; the local journal, uploading, Keychain, notifications, and distribution packaging remain future work.
