# Export Agent workspace integration

This repository owns the local macOS transport and distribution artifact. It does not own Platform device/upload contracts, provider parsing, backend completeness authority, workspace pinning, or the workspace integration runner.

## Current state

The workspace currently has no `workspace.toml`, `workspace.lock`, submodule pin set, or runnable `ws` integration profile. This repository's product CI is real, but neither a push nor a notarized Export Agent ZIP proves that compatible Platform and archive-service commits have run together. No workspace changeset is needed for this change's behavior because it changes no shared contract; a future pin/integration rollout must create one when the harness exists.

## Compatibility responsibilities

| Component | Required compatible behavior | Evidence today |
|---|---|---|
| Export Agent | Preserve and hash bytes, use existing device pairing/upload fixtures, project backend completeness truthfully, package the sandboxed app | Local tests and repository CI; notarization blocked on owner secrets |
| Contracts | Current blob-transfer and AI-archive operation/completeness shapes | Existing contract sources and fixtures; no change in this slice |
| Platform | Authenticated public device, upload, and operation boundary | Fixture-backed consumer behavior; live composition remains pending |
| ChatGPT/Claude archive services | Provider parsing and completeness authority | Owned by service repositories; no local parser added |
| Workspace harness | Pin exact compatible commits and run one synthetic end-to-end export | Not implemented |

Old agents remain compatible because this change adds no server field, route, idempotency rule, or archive semantic. They do not gain sandbox packaging or the manual update action and continue operating according to their installed local behavior. Servers require no dual routing or version negotiation.

## Required synthetic flow

1. Start pinned Platform, receiving storage, and owning ChatGPT/Claude archive services with synthetic data only.
2. Pair one sandboxed Export Agent device against Platform's public API.
3. Select a temporary inbox through the system picker and restore its security-scoped bookmark after restart.
4. Place a stable synthetic provider export in the inbox and observe hashing plus verified immutable local preservation.
5. Upload through Platform with interruption/resume and an uncertain-outcome status query.
6. Observe raw storage, provider detection, import terminal state, completeness class/warnings, and truthful local projection.
7. Retry the same digest and prove no duplicate server import and no loss of the retained local copy.

No personal export, provider credential, browser session, full path, full digest, or signing secret enters this flow or its logs.

## Rollout and rollback

Roll out in dependency order: contracts, Platform/receiver, provider archive services, then the exact notarized Export Agent commit. Record every commit SHA, fixture/schema digest, workflow run, notarized artifact digest, and integration-run URL in the workspace changeset.

Rollback the workspace pin to the last compatible Export Agent artifact and service commit set. Rollback does not delete local archives or journal state, revoke an Apple ticket, or silently install an older app. The user performs any local app replacement. A compromised signing identity follows the revocation procedure in `DISTRIBUTION.md`, independently of service rollback.

## Evidence boundary

- **Local green:** Swift/distribution tests ran on one development Mac.
- **Repository hosted CI:** the committed source and unsigned distribution policy passed on GitHub runners.
- **Owner-authorized notarization:** Apple accepted a Developer ID-signed submission, the ticket was stapled, Gatekeeper passed, and CI uploaded the final digest-addressed ZIP.
- **Clean-machine acceptance:** that ZIP launched and restored user-selected folder/Keychain behavior on another compatible Mac.
- **Workspace integration:** exact pinned client/service commits completed the synthetic flow above.

Only the final category proves workspace integration. Each earlier category remains useful evidence but cannot substitute for it.
