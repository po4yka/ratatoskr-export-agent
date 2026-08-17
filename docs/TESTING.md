# Export Agent testing strategy

Required tests:

- File events, temporary extensions, stable-size timing, duplicate notifications, permission loss, symlinks, low disk, and atomic moves.
- Streaming hash, duplicate archive identity, post-move/upload verification.
- Journal transaction/state migration, crash at every transition, restart recovery, retry schedule, cancellation.
- Keychain pairing/rotation/revoke and no-secret diagnostics.
- Upload chunk/resume/idempotency, offline/timeout/TLS/error classification, backend operation polling.
- Notification privacy and backup-age reminders.
- App lifecycle, sleep/wake, sandbox/bookmark restoration, packaging, signing/notarization/update checks.
- Workspace synthetic export-agent -> archive-service vertical flow.

Tests use synthetic ZIPs and local mock servers; no personal export or production credential is committed.
