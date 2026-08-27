## Why

The agent can preserve and journal a stable export, but it cannot yet deliver a large archive safely over an interrupted home connection. A retry must resume the same digest-addressed transfer, never create a second remote import, and make its queued/progress state visible locally.

## What Changes

- Add a digest-first, chunked upload client that consumes the fleet `blob-transfer` receipt shapes through committed fixed fixtures until a receiving service is available.
- Add a durable upload-queue projection and retry scheduler that resumes interrupted sessions from the server's received-chunk status, uses bounded exponential backoff with jitter, and does not automatically retry permanent failures.
- Make the archive digest the sole remote idempotency identity, query uncertain transfers before sending more bytes, and verify the final stored receipt against the local size and digest.
- Add validated bandwidth and concurrent-upload caps, plus a menu-bar progress/status surface derived from the same queue state.
- Add an in-process harness server and synthetic-file tests; live Platform/receiving-service integration remains explicitly pending.

## Capabilities

### New Capabilities

- `resumable-archive-upload`: Digest-first, chunk-addressed upload sessions, idempotent receipt verification, and safe recovery from interruptions.
- `durable-offline-upload-queue`: Durable retry scheduling, bounded concurrency/bandwidth, and an observable local queue state.
- `upload-progress-menu-status`: Menu-bar presentation of upload progress and queued/offline states without exposing sensitive paths or full digests.

### Modified Capabilities

- `durable-local-journal`: Extend its durable projection to retain the non-secret upload session and retry facts required to resume a queued archive safely.
- `typed-configuration`: Add validated transfer chunk, concurrency, and bandwidth configuration while retaining the one current configuration schema.

## Impact

- Affects `AgentCore` journal, configuration, URLSession transport, and new upload/retry components, plus the AppKit menu target and XCTest targets.
- Uses fleet blob-transfer fixture shapes as the fixed contract input; no service endpoint, receiver implementation, provider login, archive parsing, or server-side storage change is included.
- Requires a future integration run against the authenticated Platform edge and receiving archive service before live-upload proof can be claimed.
