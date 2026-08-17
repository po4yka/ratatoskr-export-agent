# Export Agent requirements

## Goals

1. Watch user-approved locations for completed ChatGPT/Claude export archives.
2. Fingerprint, deduplicate, and preserve original files in a local immutable archive.
3. Upload reliably to Ratatoskr using registered-device authentication.
4. Survive offline periods, crashes, restarts, sleep, and permission changes.
5. Show import/completeness status and backup-age reminders without exposing content.

## Non-goals

Logging into providers, requesting exports automatically through undocumented endpoints, parsing provider contents, browsing unrelated files, or owning backend archive semantics.

## Requirements

- Directory access is explicit and least-privilege.
- Files must be stable/closed and pass shallow ZIP/provider classification before acceptance.
- Hashing is streaming; duplicate decisions are durable.
- Original accepted archives are immutable and retained according to user policy.
- Journal transitions are crash-safe and uploads idempotent/resumable.
- Credentials live in Keychain and can be revoked.
- Notifications and logs contain no conversation/file content.

First slice: user chooses inbox/archive -> completed synthetic export detected -> hash/archive/journal -> upload -> operation/completeness status.
