# Export Agent interfaces

## Filesystem

User-selected inbox/archive URLs, security-scoped bookmarks, file coordination/events, stable-file checks, atomic move/copy, disk-space and permission state.

## Platform

Device pairing/refresh/revoke, upload create/resume/complete, operation status, completeness summary, and retry classification. Every upload uses archive hash/idempotency.

Retry classification: only a `401` carrying Platform's `platform.auth.unauthenticated` envelope costs the device pairing; any other `401` is unavailable and retried. `413` and `403` are permanent upload failures that need attention. See the README section "Which responses cost the pairing and which stop an upload".

## OS

Keychain, notifications, background task/lifecycle, sleep/wake, app launch, optional helper/LaunchAgent only after an ADR.

## Rules

The client performs shallow classification only; raw ZIP parsing belongs to ChatGPT/Claude services. Network requests use TLS, bounded chunks/timeouts, cancellation, and safe retries. Temporary files use protected user-scoped directories and deterministic cleanup. Errors identify safe state/recovery without paths or contents. Pairing is explicit and device credentials cannot authorize unrelated provider operations.
