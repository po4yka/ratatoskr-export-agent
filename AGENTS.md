# Ratatoskr Export Agent Instructions

## Scope

These instructions apply to the `ratatoskr-export-agent` repository.

This repository owns the local macOS workflow for detecting user-downloaded AI service exports, preserving them locally, and uploading them to the appropriate Ratatoskr archive service.

## Repository mission

The export agent should make snapshot-based ChatGPT and Claude backup operationally reliable without automating provider login.

It is responsible for:

- watching an explicitly configured inbox;
- detecting stable completed archive downloads;
- fingerprinting and deduplicating archives;
- preserving the original file in a local immutable archive layout;
- uploading through authenticated Ratatoskr Platform APIs;
- tracking operation/completeness results;
- retrying safely when offline;
- reminding the user when backups are stale or an export link is likely to expire;
- presenting transparent local status and errors.

It transports archives. Provider-specific parsing and archival authority remain in `ratatoskr-chatgpt` and `ratatoskr-claude`.

## Current phase

The repository is in architecture bootstrap. Do not assume a Swift app, LaunchAgent, watcher, upload client, Keychain integration, sandbox entitlements, or CI commands exist unless they are present in the checkout.

When creating initial implementation:

- start with a narrow, observable import state machine;
- keep the UI and background worker consistent through one persisted local journal;
- avoid requiring broad filesystem permissions;
- do not add browser automation as a shortcut.

### Development status

Ratatoskr is in development. No database holds data that has to survive a schema change. While this
status holds, these rules are binding, and they override anything else in this repository that
plans otherwise, including the rest of this file:

- **One version only.** The API, the database, and the contracts keep their first version. Do not
  add a `v2` or a later major version, and do not add version negotiation, deprecation windows, or
  parallel-major routing.
- **No database migrations.** Do not add a migration file, and do not add migration tooling. A
  schema change edits the current schema definition in place, and a test database is created from
  that definition.
- **The product is `Ratatoskr`.** It is not "Ratatoskr Next". Do not write that name in code,
  documentation, identifiers, comments, or commit messages.

Only the repository owner changes this status. Ask before you write anything these rules forbid.

## How a change starts

Every non-trivial change begins as an OpenSpec change rather than as an edit, and each assistant
starts one in its own syntax. Claude Code has the command: `/opsx:propose <what you want to build>`,
or `/opsx:explore` first when the shape is not clear yet. Codex has no project-level command and
triggers the same skill by name, `$openspec-propose`, or lets its description match it. OpenCode has
its own command, `/opsx-propose`. Whichever starts it, the result is `openspec/changes/<id>/` holding
a proposal, the spec deltas, a design and a task list, and you read that plan before any code is
written. `/opsx:apply`, `$openspec-apply-change` or `/opsx-apply` builds it, and `/opsx:archive`,
`$openspec-archive-change` or `/opsx-archive` folds the deltas into `openspec/specs/`.

`openspec/specs/` holds the behaviour that is true today, and it starts empty on purpose. A spec here
grows from a change that needed it. Do NOT convert `docs/REQUIREMENTS.md`, `docs/INTERFACES.md`,
`docs/DOMAIN.md` or `docs/DATA_MODEL.md` into specs in bulk. Those documents stay where they are, as
material an exploration reads. A spec set produced by bulk conversion is large, stale on the day it
lands, and trusted by nobody.

Behaviour that more than one repository can see — the shape of a contract, the meaning of a field, the
order in which repositories must receive a change — belongs in the `ratatoskr-workspace` store, not
here. `openspec/config.yaml` references it, so `openspec instructions` in this repository lists the
store's specs with the exact command that fetches one. Cite that spec from a local proposal instead
of restating it.

### Tests come first

The task list carries one pair per behaviour. The first task adds a test that fails. The second makes
it pass. Never one task that does both.

- Run the new test before you write the implementation, and confirm it fails for the reason the task
  states — not for a compile error or a typo.
- A refactor task comes after the tests are green. It adds no test and changes no behaviour.
- A task that cannot start from a failing test says why in one line. Configuration, documentation and
  generated files are the usual reasons.
- Do not tick a task whose test has not been run.

Nothing can check the order in which the two were written. What CI does check is
`openspec validate --archived`, which fails when a change was archived with a task left unticked, and
the step in `fleet.yml` that fails when a repository holds a manifest and a `ci.yml` that never runs
a test. `ratatoskr-workspace/docs/QUALITY_GATES.md` states that limit rather than implying it is
covered.

## Sources of truth

Use this order:

1. active task/changeset and accepted ADRs;
2. `README.md`;
3. upload/operation contracts from `ratatoskr-contracts` and `ratatoskr-platform`;
4. the local source archive bytes and computed hash;
5. backend import/completeness result;
6. implementation details.

The backend archive service is authoritative for provider/schema parsing. Local filename heuristics only route or label an upload candidate.

## Hard boundaries

### Export Agent owns

- local inbox/archive directory configuration;
- filesystem observation and candidate stability detection;
- local archive fingerprint/journal state;
- local duplicate detection;
- registered-device credential storage/use;
- upload queue, retries, and operation tracking;
- local reminders and notifications;
- user-visible local diagnostics;
- local preservation/copy/move status.

### Export Agent does not own

- ChatGPT or Claude parser schemas;
- project/conversation/file normalized data;
- backend completeness authority;
- OpenAI or Anthropic inference;
- provider passwords, browser cookies, MFA, or consumer sessions;
- generic email account access unless introduced as a separately scoped connector/ADR;
- server-side retention or BlobStore policy;
- other services' database state.

Do not parse provider exports deeply enough to become a second independent archive implementation.

## Prohibited behavior

Never implement:

- automatic ChatGPT or Claude web login;
- password or MFA collection;
- browser cookie/session extraction or replay;
- automatic clicking/downloading from provider export links using a logged-in session;
- undocumented consumer API calls;
- hidden browser automation;
- content scanning for analytics unrelated to backup;
- upload to endpoints other than the explicitly configured Ratatoskr instance;
- deletion of the user's only archive copy after upload.

A reminder may guide the user to request/download an official export, but the user performs provider authentication and download.

## Local filesystem scope

Use the narrowest possible filesystem access.

Recommended conceptual locations:

```text
Ratatoskr Inbox/
Ratatoskr Archive/<provider>/<year>/<month>/
Ratatoskr State/
```

Rules:

- use user-selected security-scoped bookmarks or explicit configuration where sandboxing requires it;
- do not scan the entire home directory or Downloads recursively by default;
- never follow untrusted symlinks outside the allowed roots;
- validate paths before copy/move/delete;
- preserve original bytes;
- use collision-safe names independent of untrusted archive filenames;
- write state and copied files atomically where possible;
- distinguish user-managed originals from agent-managed archived copies;
- never delete unrelated files during cleanup.

## Detecting completed downloads

A file appearing in the inbox may still be downloading.

Before hashing/uploading:

- ignore known temporary/partial download suffixes;
- require a stable file size/modification state across a bounded quiet period;
- verify the file is readable and not currently exclusively locked where the platform permits;
- reject directories, devices, links, and unsupported special files;
- cap file size according to configured upload limits;
- record candidate discovery and stability evidence;
- handle rename-from-temporary patterns;
- make repeated filesystem events idempotent.

Do not rely on a single filesystem notification as proof that the archive is complete.

## Provider detection

Provider detection may use safe bounded evidence such as:

- filename hints;
- archive top-level filenames;
- small manifest/schema probes performed with archive safety limits;
- user selection when ambiguous.

Rules:

- provider detection is advisory routing, not schema authority;
- never fully extract untrusted archives locally merely to identify them;
- ambiguous candidates require user choice or backend generic intake;
- record the detection method/confidence;
- preserve unknown provider candidates without misrouting destructive actions.

The backend parser decides the actual detected schema and completeness.

## Local fingerprint and journal

Compute a cryptographic hash, normally SHA-256, before upload.

Persist a local journal containing at least:

- local candidate/archive ID;
- provider hint;
- original and agent-managed paths;
- byte size and hash;
- discovered/stable/archived/uploaded timestamps;
- upload idempotency key;
- backend operation ID;
- upload attempt state and failure class;
- backend archive/import/completeness references;
- notification/reminder state.

Rules:

- journal transitions are idempotent;
- identical content hashes are not uploaded repeatedly without explicit reason;
- a previous failed/partial import may be retried using the same archive identity;
- journal corruption/failure must not delete source archives;
- sensitive path information is not sent to backend unless required and sanitized.

## Local preservation

Before or alongside upload:

- copy the source to the configured agent-managed archive using an atomic temporary destination;
- verify the copied size/hash;
- retain original provider filename only as metadata/sanitized display data;
- use a content hash or stable generated ID in the managed filename;
- preserve file creation/download timestamps as metadata where useful;
- never overwrite a different archive because filenames collide;
- do not remove the user's original unless the user explicitly enables and confirms a cleanup policy;
- cleanup policy must preserve at least one verified local copy.

A backend success does not automatically authorize local deletion.

## Device authentication

The agent authenticates to Ratatoskr as a registered device, not with provider credentials.

- Store device secrets/tokens in macOS Keychain.
- Scope credentials to the configured Ratatoskr instance and required upload/operation permissions.
- Support revocation and re-registration.
- Validate TLS and endpoint identity; do not offer a silent insecure fallback.
- Do not put tokens in preferences, command-line arguments, logs, crash reports, or exported diagnostics.
- Separate multiple Ratatoskr instances/profiles explicitly.
- Show connection/account identity to the user before upload.

## Upload protocol

Uploads must be resumable or safely retryable for large archives.

Rules:

- use an idempotency key tied to local archive identity/hash;
- send provider hint, size, hash, and acquisition metadata through the documented contract;
- stream bytes rather than reading the entire archive into memory;
- bound memory and network concurrency;
- verify backend acknowledgment includes the expected hash/size or archive reference;
- persist operation ID before considering the request accepted;
- classify auth, network, size, policy, validation, and server failures;
- honor cancellation without corrupting local state;
- do not retry permanent validation/policy failures automatically;
- resolve uncertain network outcomes by querying operation/archive status before re-uploading.

The agent never uploads to `ratatoskr-chatgpt`/`ratatoskr-claude` internal ports directly; it uses Platform's authenticated public API.

## Offline queue and retries

- The queue is durable across app/agent restart.
- Network reachability is a hint, not proof; actual requests determine availability.
- Use bounded exponential backoff with jitter.
- Respect server retry hints.
- Bound simultaneous uploads.
- Allow manual retry/pause/cancel.
- Preserve source/managed archive through all retry states.
- Avoid repeated user notifications for the same continuing failure.
- Reauthenticate explicitly on revoked/expired device credentials.

Do not spin continuously or consume excessive battery/CPU while offline.

## Backend operation and completeness tracking

After upload, track the backend operation until a terminal state.

Display separately:

- upload completed;
- raw archive stored/verified;
- provider/schema detected;
- import completed/partial/failed;
- projects/conversations/assets counts where backend exposes them;
- completeness class and warnings;
- missing assets/unknown records;
- link to open the detailed report.

Do not convert a backend `partial` result into local success without warnings. Do not claim backup completeness based only on upload completion.

Operation updates may be duplicated or out of order. Apply sequence/version checks and idempotent projection.

## Reminders and stale-backup policy

Reminders are local user assistance, not provider automation.

Possible policies:

- remind when no successful raw archive has been stored for N days;
- distinguish ChatGPT and Claude freshness;
- alert when a downloaded archive is detected but not uploaded;
- remind that provider download links may expire;
- suppress reminders after a recent successful import;
- allow per-provider disable/snooze.

Rules:

- use local notification APIs;
- keep content private and generic on the lock screen by default;
- do not infer a provider email/link exists unless an integrated source actually observed it;
- do not repeatedly nag after an acknowledged/snoozed reminder;
- store reminder state locally and transparently.

## UI and background-agent consistency

- Use one persisted source of truth for queue/journal state.
- UI commands enqueue explicit operations rather than mutating filesystem/network state behind the worker.
- Background execution obeys macOS lifecycle, sandbox, power, and notification constraints.
- Show clear paths, provider hint, hash prefix, size, state, last attempt, and actionable error.
- Provide safe reveal/open actions without executing archive contents.
- Avoid rendering archive HTML or messages in the agent.
- Destructive local cleanup requires explicit confirmation and shows what copy remains.

## macOS security and distribution

When implementation reaches distribution:

- use App Sandbox where compatible with the chosen filesystem workflow;
- use security-scoped bookmarks for user-selected folders;
- store secrets in Keychain;
- define minimal entitlements;
- sign, harden, notarize, and validate the distributed app/agent;
- avoid privileged helpers unless an ADR proves necessity;
- make LaunchAgent/login-item behavior explicit and user-controllable;
- provide a clean uninstall path that does not delete archives silently.

Do not commit signing certificates, provisioning credentials, notarization secrets, or Developer ID material.

## Privacy and logging

AI export archives contain highly sensitive conversations and files.

- Do not inspect message content for routing, telemetry, or notifications.
- Do not log archive contents, filenames, full paths, titles, hashes in full, device tokens, or backend private errors by default.
- Use hash prefixes/local IDs for diagnostics.
- Keep diagnostics export opt-in, redacted, and reviewable.
- Do not upload crash attachments containing archives or journal secrets.
- Protect local journal/archive permissions.
- Audit local deletion and portable diagnostic export where implemented.

## Observability

Local telemetry/status should cover:

- watcher health and last event;
- candidates discovered/stabilized/rejected;
- bytes hashed/copied/uploaded;
- duplicate detection;
- queue depth and retry state;
- upload/operation duration and failure class;
- backend completeness outcomes;
- reminder state;
- app/agent version and configured endpoint in non-sensitive form.

Prefer local diagnostics. Remote telemetry must be explicit, privacy-preserving, and disabled/configurable according to product policy.

## Testing expectations

When implementation exists, include applicable tests for:

- filesystem event deduplication and rename patterns;
- stable-file/quiet-period detection;
- partial-download suffixes and locked files;
- path/symlink/special-file safety;
- streaming hash and copy verification;
- filename collisions and atomic publication;
- local journal state-machine recovery/corruption handling;
- duplicate archive behavior;
- Keychain/device credential abstraction;
- TLS/auth/revocation handling;
- resumable/idempotent upload and uncertain outcomes;
- offline backoff/pause/cancel;
- out-of-order backend operation updates;
- completeness/partial result display;
- reminder suppression/snooze;
- sandbox/security-scoped bookmark behavior;
- no-content logging guarantees.

Use synthetic archives. Never commit or transmit personal ChatGPT/Claude exports in tests.

## Cross-repository change rules

Use a workspace changeset when changing:

- Platform upload/device/operation contracts;
- ChatGPT/Claude acquisition metadata;
- backend completeness/result contracts;
- local archive/hash/idempotency semantics;
- macOS distribution/deployment integration;
- web deep links for reports.

List producer/consumer compatibility, rollout, rollback, old-agent behavior, privacy, and user-visible impact.

## Git and PR workflow

- State whether the change affects watcher, local archive, journal, auth, upload, operation tracking, reminder, UI, or distribution.
- Keep provider-neutral transport separate from backend parser semantics.
- Include filesystem/network failure tests.
- Document permissions, entitlements, local paths, deletion, and privacy impact.
- Do not add provider login/session automation.
- Do not commit personal archives, device tokens, full local paths, signing secrets, or screenshots with private data.
- Do not claim raw/archive completeness beyond the backend result.
- Update README/ADRs when filesystem, auth, background, or product boundaries change.

## Completion criteria

A task is complete only when:

- responsibility belongs to the local export agent;
- provider login/session/password/cookie automation is absent;
- filesystem scope and path handling are minimal and safe;
- incomplete downloads are not hashed/uploaded prematurely;
- original bytes are fingerprinted and at least one verified local copy is preserved;
- local journal/upload operations are durable and idempotent;
- device secrets remain in Keychain and TLS is verified;
- backend partial/completeness results are displayed truthfully;
- offline/retry/reminder behavior is bounded and user-controllable;
- privacy-sensitive content is absent from logs/telemetry;
- relevant macOS, filesystem, network, and state-machine tests pass;
- contracts and cross-repository rollout are documented.
