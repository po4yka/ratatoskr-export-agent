## Context

The package already has typed watched-folder access state, an append-only journal, a privacy-safe upload queue projection, and an injected notification service. The menu-bar executable currently exposes upload/import rows and a folder settings window. See `proposal.md` for the operational gap and the delta specs for observable requirements.

This change is local-only: no cross-repository contract or update service exists. Journal corruption is a fail-closed condition, notification authorization belongs to macOS, and support data may originate near highly sensitive paths, filenames, URLs, and archive contents.

## Goals / Non-Goals

**Goals:**

- Keep reminder decisions deterministic and independently testable with injected time.
- Assemble diagnostics from typed observations without passing source errors or sensitive strings through to UI or export.
- Make the previewed support report bytes identical to the exported bytes.
- Extend the existing menu/settings shell with an operational diagnostics surface.

**Non-Goals:**

- Provider backup-age reminders, provider login automation, remote telemetry, backend support upload, update discovery, packaging, signing, or distribution.
- Persisting filenames, URLs, content excerpts, or new archive lifecycle facts in the journal.
- Treating a readable journal, upload completion, or available disk space as proof of backend completeness.

## Decisions

### Model reminders as a pure folder-level policy plus a small persisted suppression document

`AgentCore` will accept opaque folder IDs and item observations containing only discovery time and processed state. A positive threshold, injected clock, notification authorization, snooze time, and last-delivered condition produce an explicit decision. A compact local reminder-state document records only folder UUID, delivered-condition marker, snooze time, and evaluation time; it is replaced atomically and uses the current schema directly.

Folder-level suppression avoids repeated notices for every file in one troubled directory. The condition resets only after no item remains eligible, which makes reminders gentle and deterministic. An alternative of deriving reminders from `JournalEntry` was rejected because items can be stuck before journal insertion and the journal deliberately lacks source discovery time.

### Reuse the notification permission boundary with a generic notice value

The current notification service will accept a privacy-safe notice shared by terminal import and reminder coordinators. The platform adapter continues to read the existing authorization decision and never requests permission as a side effect of diagnostics. An alternative separate reminder service would duplicate permission and delivery semantics.

### Assemble one immutable diagnostics snapshot from typed probes

A diagnostics assembler will receive folder access observations, notification authorization, a disk-capacity probe for the agent-managed archive root, a journal-health result, queue status, and a constant deferred update status. Results use enums and counts rather than raw errors or locations. Journal safe-stop produces `requiresAttention` and an unavailable queue projection rather than projecting untrusted bytes.

The SwiftUI view model owns refresh timing and bridges async notification authorization; the assembler stays pure. The panel reads the same registry/journal projection used by the worker rather than maintaining a parallel operational database.

### Make support report input a closed data model

The report builder consumes the immutable diagnostics snapshot and explicitly sanitized item summaries. Default item summaries can carry only local UUID, state, byte count, attempt count, and a fixed-length digest prefix. No `[String: Any]`, free-form diagnostic string, raw `Error`, `URL`, or filesystem `URL` is accepted.

Optional sensitive fields are expressed as a set of field selections keyed by one item UUID. Values are copied only after the UI displays them for review, with strict length bounds; filesystem paths and credential-shaped values are refused even when selected. This satisfies explicit per-item inclusion without turning a global switch into broad disclosure.

The builder creates deterministic JSON `Data`; preview decodes/displays those bytes and export writes the same bytes through a user-selected save panel using an atomic replacement. An alternative post-encoding regex scrubber was rejected because redaction after construction is incomplete by nature and difficult to prove.

### Keep update checking as an inert typed state

Diagnostics will expose `deferredPendingDistributionDecision`. There is no URL, client protocol, timer, network call, preference, or update entitlement. Item 10 can replace this state only after choosing the distribution/update model. A fake checker or placeholder endpoint was rejected because it would claim a capability and security boundary that does not exist.

## Risks / Trade-offs

- [Pre-journal watched-item age is not currently durable] → Persist only bounded reminder observation/suppression facts and rebuild eligibility from watcher reconciliation; never add source paths to the journal.
- [Disk capacity can change immediately after probing] → Present it as a current diagnostic observation, not a reservation or write guarantee.
- [Explicit detail can disclose user-selected sensitive data] → Require per-item, per-field selection, show the exact final bytes, bound values, and never allow credentials or paths.
- [A one-shot continuing-condition reminder may remain silent for a long incident] → Prefer non-nagging behavior now; clearing the condition or an explicit user reset rearms it.
- [The bootstrap app has limited runtime composition] → Add dependencies through narrow factories and keep unavailable observations truthful rather than synthesizing healthy defaults.

## Migration Plan

1. Add tests and models without changing existing journal record encoding.
2. Add the reminder-state file as a new atomic local document; absence means no prior reminder and requires no migration.
3. Add the diagnostics panel/menu entry and support-report save flow.
4. Validate targeted tests, the full local gate, and release smoke behavior before integration.

Rollback removes the new panel, reminder document, and coordinators. Existing archive, journal, folder preferences, Keychain, and upload state remain readable because their formats do not change.
