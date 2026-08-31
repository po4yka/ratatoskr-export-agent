## Why

The packaged Export Agent launches a static menu shell while its watcher, immutable archive store,
journal, pairing, resumable queue, polling, reminders, and notifications remain disconnected. Its
journal and transports also cannot route mixed providers or resume one Platform operation with a
rotated credential after relaunch.

## What Changes

- **BREAKING** Replace the incomplete development journal shape in place with per-entry provider,
  classification, operation, transfer, retry, and last-observation state; reject incompatible old
  documents without deleting managed archives.
- Implement the operation-bound Platform open/chunk/status/finalize transport and acquire a current
  device credential for every request.
- Persist Platform origin and non-secret paired identity, keeping all secret material only in
  non-synchronizing Keychain.
- Compose exactly one actor-owned operational runtime from the app delegate and connect watcher,
  preservation, queue, polling, lifecycle reconciliation, UI actions, reminders, diagnostics, and
  privacy-safe notifications.
- Publish only an exact integrated, signed, notarized, stapled, Gatekeeper-accepted application to
  an immutable GitHub Release with checksum; add a separate clean-machine acceptance contract.

## Capabilities

### New Capabilities

- `operational-agent-runtime`: One durable lifecycle-aware runtime drives the installed product flow.

### Modified Capabilities

- `durable-local-journal`: Every entry owns provider and resumable operation state.
- `resumable-archive-upload`: Transfer resumes missing chunks inside the same prepared operation.
- `platform-device-pairing`: Relaunch restores non-secret identity while Keychain remains the sole
  secret store and every request observes current session authority.
- `durable-offline-upload-queue`: Mixed-provider retry, pause, cancel, and restart behavior is
  per-entry and bounded.
- `backend-import-status`: UI/history retain truthful last-known and terminal Platform observations.
- `app-shell`: Onboarding and operational controls observe and act on the shared runtime.
- `macos-direct-distribution`: Owner-authorized publication produces an immutable trusted release.
- `manual-application-update`: The update destination resolves to the accepted release artifact.

## Impact

This changes AgentCore journal/transport/session/runtime APIs, the AppKit/SwiftUI composition root,
settings/menu/history/diagnostics, lifecycle and launch-at-login handling, tests, entitlements, and
the distribution workflow. It adds no provider automation, broad filesystem access, automatic
updater, helper, credential logging, or deletion of the only local archive.
