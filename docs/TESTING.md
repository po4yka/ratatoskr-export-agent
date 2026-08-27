# Export Agent testing strategy

Required tests:

- File events, temporary extensions, stable-size timing, duplicate notifications, permission loss, symlinks, low disk, and atomic moves.
- Streaming hash, duplicate archive identity, post-move/upload verification.
- Journal transaction/state handling against the current schema, crash at every transition, restart recovery, retry schedule, cancellation.
- Keychain pairing/rotation/revoke and no-secret diagnostics.
- Upload chunk/resume/idempotency, offline/timeout/TLS/error classification, backend operation polling.
- Notification privacy plus watched-item reminder threshold, suppression, snooze, and rearm behavior.
- Diagnostics assembly for mixed folder permission, notification, disk, journal, queue, and manual-update/version states.
- Support-report canaries proving default filename/path/content/URL/credential/full-digest redaction,
  explicit per-item field inclusion, prohibited-value refusal, and preview-byte-identical local export.
- App lifecycle, sleep/wake, sandbox/bookmark restoration, packaging, signing/notarization/update checks.
- Workspace synthetic export-agent -> archive-service vertical flow.

Tests use synthetic ZIPs and local mock servers; no personal export or production credential is committed.

`Tests/Distribution/run.sh` assembles the `.app`, validates exact bundle metadata and entitlements,
rejects unsigned/ad hoc release claims, and launches an ad hoc sandbox smoke bundle. Those checks do
not prove Developer ID, Apple notarization, stapling, Gatekeeper acceptance on a clean Mac, or workspace
integration. The manual owner-authorized workflow is the only hosted notarization path, and its current
credential blocker is recorded in `DISTRIBUTION.md`.

## Test-first

A change is planned before it is built, and the plan is a task list in which behaviour arrives in
pairs: one task adds a failing test, the next makes it pass. `openspec/config.yaml` carries that
rule, which is what puts it into every planning and implementation request rather than only into this
document.

The loop:

1. Write the test the scenario names. Run it. Confirm it fails, and read the failure — a test that
   fails because it does not compile has proved nothing about the behaviour.
2. Write the smallest change that makes it pass. Run it again.
3. Refactor only once it is green, adding no test and changing no behaviour.

Two checks stand behind this, and neither of them can see the order:

- `openspec validate --archived`, in `.github/workflows/openspec.yml`, fails when a change was
  archived with a task left unticked.
- A step in `.github/workflows/fleet.yml` fails when this repository holds a manifest and a `ci.yml`
  that never runs a test.

`ratatoskr-workspace/docs/QUALITY_GATES.md` records why the order itself is not checkable, rather
than leaving the gap to be discovered.
