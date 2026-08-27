## Why

The agent can preserve and queue a local export and can poll a known Platform operation, but it
does not yet create or bind that operation while uploading. This leaves backend import tracking
disconnected from the archive the user actually selected.

## What Changes

- Add an authenticated, operation-bound Platform archive transport for ChatGPT and Claude.
- Create the operation from the locally verified provider, SHA-256 and byte length before sending
  archive bytes, persist its ID in the existing journal, and stream the already-managed copy to
  the fixed operation content URL.
- Treat acknowledgement uncertainty safely: retain the operation binding and let the existing
  polling path recover the authoritative result rather than creating a second upload.
- Keep archive bytes local and opaque to the agent beyond the existing hash/size evidence.

## Capabilities

### New Capabilities

- `operation-bound-archive-upload`: durable agent submission of a locally archived export through
  Platform's archive-operation contract.

### Modified Capabilities

- None.

## Impact

- `AgentCore` upload transport, queue integration, and XCTest fixtures.
- The existing Platform archive-operation endpoint and the workspace `operation-progress` contract
  are consumed; no provider credentials or parser semantics are added.
