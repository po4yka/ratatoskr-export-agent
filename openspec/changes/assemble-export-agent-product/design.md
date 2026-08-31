## Context

See `proposal.md`. AgentCore already contains independently tested watcher, classifier, immutable store, journal, generic resumable uploader, device session, polling, notification, reminder, diagnostics, and distribution primitives. The application currently instantiates only a static menu plus independent settings and diagnostics readers. The production archive transport is operation-bound but whole-file and fixed-token, while the generic chunk transport is resumable but not operation-bound or authenticated.

## Goals / Non-Goals

**Goals:**

- Make provider route and operation transfer recovery durable per archive.
- Use one request-scoped device session authority for all Platform requests.
- Compose one lifecycle-aware runtime and one privacy-safe UI projection.
- Preserve strict sandbox, HTTPS, Keychain, and immutable local-copy boundaries.
- Make release publication immutable and keep external Apple/clean-machine proof explicit.

**Non-Goals:**

- Provider login, browser automation, provider export parsing, automatic updates, helpers, LaunchAgents, broad filesystem access, or deletion of the only archive copy.
- A second journal/API version, compatibility decoding, or migration tooling.
- Treating local fixtures as live Platform, Apple, or clean-machine evidence.

## Decisions

### Per-entry route and split operation state

`JournalEntry` gains a required immutable route/classification/policy value. A separate operation transfer checkpoint owns operation ID, upload session, acknowledged chunks, and finalization; backend observation remains the last truthful Platform status. This prevents a prepared operation from being mistaken for a terminal result. Old development records missing the required route fail closed through the existing checked journal envelope and are never rewritten.

Alternative: keep queue-wide providers or infer provider from managed paths. Rejected because either loses mixed-provider correctness or trusts local path text as authority.

### Operation-bound chunk protocol

The production transport exposes prepare, open, status, chunk, and finalize. The queue persists operation/session state before publishing progress, asks status after restart, and streams only missing chunks. The generic blob transport remains a testable primitive but is not the production Platform route.

Alternative: wrap the existing whole-file PUT in retries. Rejected because uncertain outcomes and process interruption cannot prove same-operation resume.

### Session coordinator owns authenticated request recovery

Platform transports request a credential for every request from one coordinator. On a 401, the coordinator invalidates the rejected access credential, rotates or reopens once, and permits only one replay of an idempotent request. A second refusal clears Keychain authority and publishes re-pairing-required without touching archives or the journal.

Alternative: inject a token string when constructing each transport. Rejected because it freezes authority across rotation and cannot coordinate revocation.

### One actor-owned runtime

One runtime owns components and loop task handles; the app delegate owns that runtime. Startup, wake, and network recovery feed a coalescing reconciliation method. A main-actor projection exposes redacted state and actions to every menu/window. Smoke mode installs presentation only and never constructs live networking.

Alternative: let each window reopen state and start its own worker. Rejected because it duplicates work and can observe an append mid-transition.

### Direct release with a separate acceptance boundary

The notarization job retains read-only repository permission. A dependent release job receives only validated ZIP/checksum artifacts and the minimal contents-write permission, verifies an existing immutable tag points to the exact source revision, refuses an existing release or asset, and creates the release last. A clean-machine script validates trust automatically and records human-only product steps without disabling Gatekeeper or overwriting applications.

## Risks / Trade-offs

- [Old development journals become unreadable] -> fail closed with a clear error and leave journal plus managed ZIP bytes unchanged.
- [Provider classification is ambiguous or social] -> preserve/refuse safely and never route Instagram, Threads, or unidentified archives to an AI receiver.
- [401 retry duplicates a mutation] -> replay only operation-scoped idempotent requests with stable operation/session/chunk identity.
- [Lifecycle signals arrive in bursts] -> coalesce them and track in-flight entry IDs in the runtime actor.
- [Main-app login registration is unavailable outside an installed app] -> expose truthful disabled/error state; use no helper fallback.
- [Apple credentials or a second Mac are absent] -> implement and statically validate publication/acceptance policy while leaving external acceptance open.

## Migration Plan

1. Land compatible Platform operation routes before publishing this client.
2. Replace the development journal schema in place; incompatible journals safe-stop and managed archives remain recoverable by the user.
3. Validate repository tests and the exact-revision workspace profile before creating a release tag.
4. Publish only after the immutable tag and trusted artifact checks pass.
5. Roll back by installing the previous accepted ZIP; never rewrite journal state or delete retained archives automatically.
