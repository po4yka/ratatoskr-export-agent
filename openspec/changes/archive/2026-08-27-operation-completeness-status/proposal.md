## Why

After an archive is uploaded, the agent currently has no persisted view of the backend import
operation. A user cannot tell whether the archive is still processing, complete, partial, or
failed, and an unreachable backend could be mistaken for a successful import.

## What Changes

- Persist a privacy-safe backend operation/completeness projection beside each local archive and
  poll the authenticated Platform operation endpoint.
- Decode only the workspace-defined AI archive result summary; map real operation and summary
  payloads to per-archive status without locally interpreting export contents.
- Present the projection in the app status UI, including the last-observed time when polling is
  unreachable, and send generic terminal notifications only with system permission.

## Capabilities

### New Capabilities

- `backend-import-status`: Durable backend-operation tracking and truthful per-archive import
  presentation.
- `terminal-import-notifications`: Permission-gated, privacy-safe local notifications for terminal
  import outcomes.

### Modified Capabilities

- `durable-local-journal`: Journal entries retain backend-operation observation and notification
  state needed across restart.

## Impact

Affected areas are `AgentCore` journal/transport/status projection, the AppKit menu presentation,
and XCTest fixtures. The consumer relies on workspace change
`archive-operation-completeness-projection`; it does not change provider parsing, API versions,
Keychain handling, or provider-login boundaries.
