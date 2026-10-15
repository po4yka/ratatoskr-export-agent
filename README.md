# Ratatoskr Export Agent

`ratatoskr-export-agent` is the local macOS companion for importing official ChatGPT and Claude data exports into Ratatoskr. It watches a user-controlled inbox, identifies provider archives, verifies and submits them to the local Ratatoskr deployment, preserves the original files, and reports backup freshness and import completeness.

> **Status:** bootstrap core delivered as a SwiftPM package. It includes the menu-bar shell, watched-folder configuration and observation, completed-download checks, streaming fingerprinting, bounded classification, immutable local preservation, a fail-closed journal, resumable queue primitives, device pairing/Keychain support, operation polling, local reminders, operational diagnostics, and a manual update link. The repository packages a sandboxed `.app`, validates its three-entitlement allowlist, and provides fail-closed Developer ID/notarization CI. Owner signing and notary credentials are absent, so no notarized artifact has been produced. Authenticated live archive upload composition, background lifecycle wiring, clean-machine distribution acceptance, and workspace pinning remain pending.

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

The default `maxArchiveBytes` is 2 GiB, equal to Platform's default archive ceiling (`archive_staging.max_archive_bytes`). When Platform answers a prepare or chunk request with HTTP 413 (`payload_too_large`), the failure is permanent: the entry stops automatic retry, keeps its preserved archive, and shows as an upload that needs attention until the user retries it. Lower `maxArchiveBytes` or raise the Platform ceiling so the two agree.

### Which responses cost the pairing and which stop an upload

Only Platform's own authentication verdict costs the device pairing: a `401` whose body is an error envelope with code `platform.auth.unauthenticated`. The agent refreshes the credential once and resends; if the answer is again that `401`, it removes the stored credential and asks the user to pair again. Any other `401` (another envelope code such as `claude.auth.unauthenticated` relayed from a receiver, an empty body, or a body that is not an error envelope) is not a verdict on the device credential: after the same single refresh it is treated as unavailable, retried with backoff, and never removes the pairing.

Two responses stop an upload without touching the pairing: `413` (`payload_too_large`) and `403` (for example `chatgpt.account.unmapped`, a Platform user the receiver has not set up). Both are permanent: the entry stops automatic retry, keeps its preserved archive, and shows as an upload that needs attention until the user retries it.

### How Platform answers are classified and when retries end

The agent classifies every failed answer by route (XR-021 CONTRACTS.md section R5-05):

| Route | Answer | The agent |
| --- | --- | --- |
| any | `401` with `platform.auth.unauthenticated`, `403`, `413` | permanent (see above) |
| `prepare`, `open` | `400`, `422`, `409` (`409` is the same idempotency key with another body) | permanent |
| `prepare`, `open` | `404` (Edge has not observed the receiver yet) | retry with backoff, counted by the attempt bound |
| `status`, `chunk`, `finalize` | `404` (Edge expired, failed or dropped the token) | reopen the session |
| `chunk`, `finalize` | `400` | retry; the next attempt reconciles through `status` |
| any | `408`, `429`, `5xx` | retry with backoff, honouring `Retry-After` |
| any | any other `4xx` | permanent |

When no route rule applies and the body parses as an error envelope, its `retryable` member decides: `retryable: true` retries an otherwise permanent `4xx`, and `retryable: false` on a `5xx` or `429` is permanent. The route rules come first because Platform marks the `404` for a dead session `retryable: false`, yet reopening is the recovery.

A resumption token that Edge dropped is not retried: the agent discards the token and the acknowledged chunks, and the next run opens a new session for the same operation with a new `Idempotency-Key` (the journal key plus `/session-<n>`) and sends the chunks again. One entry reopens at most `maxSessionReopens` times (default 3, kept in the journal checkpoint); the fourth drop fails the entry with the reason `session_expired`.

Retries are bounded. `UploadRetryPolicy.maximumAttempts` (default 24, about one day at the 5 s initial delay doubling to the 3600 s cap) counts consecutive retryable failures; the next one fails the entry with the reason `retries_exhausted`. A capacity deferral does not count, and a chunk the receiver acknowledged resets the count. A failed entry shows its reason in the status menu ("Upload failed (retries exhausted)", "Upload failed (session expired)"), keeps its preserved archive, and waits for Retry Now, which gives it a fresh attempt and reopen budget.

## Obsidian vaults (the `cli` channel)

The agent can also send an Obsidian vault to `ratatoskr-notes` without Obsidian Sync and without
the plugin (workspace change `add-notes-vault-connections`, OBS-023).

- **Add a vault.** Settings → Obsidian vaults → Add Vault…, and pick the vault folder. The registry
  keeps a security-scoped bookmark, the folder name and the vault key in `vault-preferences.json`
  of the support directory.
- **Vault key.** The key is the vault id of Obsidian, the same key that the plugin sends, so notes
  keeps one channel per vault. The agent reads it from `obsidian.json` of the account. The
  sandboxed build cannot read that file until the owner selects it once with "Allow reading the
  Obsidian vault list…" in the vault settings; the agent keeps a security-scoped bookmark of it in
  `obsidian-config.bookmark` (no new entitlement). Without that grant, the agent generates a key
  once per vault, and that key is not the key of the plugin. After the grant, the next reconcile
  gives such a vault the key of Obsidian and removes the saved connection of the old key, so the
  vault connects again with the right key. The notes connection of the old key stays until the
  owner removes it.
- **Sends.** One sync per vault watches the folder with FSEvents, connects (`POST
  /v1/notes/connections` with channel `cli`), sends the manifest, and then sends the change
  batches. The connection id and the committed sequence are in `vault-channels.json`, so a restart
  resumes the same connection with the manifest first. No secret is in these files.
- **Failures.** A failed send or start is tried again after 5 seconds, doubled up to 5 minutes, with
  jitter. More than 10 000 waiting changes become one manifest. These answers stop the vault, and
  the menu names the cause: `notes.channel_mismatch`, a removed connection (`410
  notes.connection.removed`), `409 notes.connection.vault_already_connected`, `400
  notes.request.invalid`, and a manifest over 100 000 entries or 32 MiB. A change that lacks its
  hash or length takes them from its file, or the agent sends a manifest. A `vault-channels.json`
  that does not decode is moved to `vault-channels.json.corrupt-<seconds>`, and the agent starts
  with no saved connections.
- **Writes.** When the owner turns on the write mode of the connection (workspace change
  `add-notes-write-back`, OBS-024), notes keeps the checked writes in a queue of the connection. Each
  vault sync reads it every 15 seconds (`GET /v1/notes/connections/{id}/device-operations`) and
  applies the operations in order. Before an operation, the agent compares the hash of the local
  file with the base hash; when they differ, it changes nothing, reports `base_mismatch` and sends
  the local file. It applies `create`, `rename`, `move`, `delete` and `set_property` with the
  Obsidian CLI (`obsidian rename` and `obsidian move` update the links, and `obsidian delete` moves
  the file to the trash and never gets `permanent`), and `update` with an atomic write in the vault
  folder. A path that resolves outside the vault, or that has a segment that starts with `.`, is
  refused. Its own changes come back through the watcher, and notes takes them as the
  acknowledgements of the writes.
- **Obsidian 1.12.7 or later.** The writes need the Obsidian CLI, which the Obsidian installer 1.12.7
  or later registers (Settings → General → Command line interface). The CLI answers only while the
  app runs, and its first command starts the app. So the agent does not run the CLI while Obsidian
  does not run, and never starts Obsidian for a write: the operations stay in the queue, and their
  notes operations stay `running`.
- **Menu.** Each vault shows connecting, connected, offline and trying again, or stopped with its
  cause. A vault whose connection the owner removed, or that already has another connection, has
  Connect Vault <name> Again, which forgets the saved connection and connects again.

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
watched-folder access counts
notification authorization
available disk capacity
journal health and entry count
queue depth by operational state
update-check decision state
```

The status-menu Diagnostics panel reads these facts from the existing preferences and journal stores.
Its support report uses a closed schema of digests, counters, sizes, and bounded states; by default it
cannot encode filenames, paths, contents, credentials, full hashes, private errors, or endpoint URLs.
The complete JSON is shown before the same bytes are atomically saved to a user-chosen local file.
There is no report upload path. Per-item detail APIs require an explicit item-and-field selection and
still reject filesystem paths and credentials.

Watched-item reminders use an injected threshold and persist only opaque folder IDs plus suppression
and snooze state. One continuing condition produces at most one generic notification, clears to rearm,
and stays quiet when notifications are denied or the folder is snoozed.

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
8. Add local watched-item reminders and operational diagnostics. (Delivered)
9. Add hardened sandbox, signing, notarization, and the distribution-selected update mechanism. (Structure delivered; owner-authorized notarization blocked)
10. Validate real ChatGPT and Claude export workflows end to end.

## Workspace integration

The product CI now covers Swift and unsigned distribution behavior. The planned workspace harness
still does not exist and therefore cannot pin this Export Agent with compatible Platform, ChatGPT,
Claude, and AI-archive commits or run the synthetic vertical flow. [Workspace integration notes](docs/WORKSPACE_INTEGRATION.md)
define compatibility, rollout, rollback, privacy, and the evidence required before claiming that
integration. Real personal exports remain outside repositories and public CI.

## Project status

The local workflow, sandbox bundle structure, manual update action, and release pipeline now exist.
Local and normal-CI checks cannot sign or notarize without owner material; see
[distribution evidence and blockers](docs/DISTRIBUTION.md). A push is not proof of hosted notarization,
clean-machine acceptance, live archive integration, or workspace compatibility.
