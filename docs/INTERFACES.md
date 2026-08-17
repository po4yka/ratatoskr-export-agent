# Export Agent interfaces

## Filesystem

User-selected inbox/archive URLs, security-scoped bookmarks, file coordination/events, stable-file checks, atomic move/copy, disk-space and permission state.

## Platform

Device pairing/refresh/revoke, upload create/resume/complete, operation status, completeness summary, and retry classification. Every upload uses archive hash/idempotency.

## OS

Keychain, notifications, background task/lifecycle, sleep/wake, app launch, optional helper/LaunchAgent only after an ADR.

## Rules

The client performs shallow classification only; raw ZIP parsing belongs to ChatGPT/Claude services. Network requests use TLS, bounded chunks/timeouts, cancellation, and safe retries. Temporary files use protected user-scoped directories and deterministic cleanup. Errors identify safe state/recovery without paths or contents. Pairing is explicit and device credentials cannot authorize unrelated provider operations.
