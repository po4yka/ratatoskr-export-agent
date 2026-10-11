## Why

After the whole archive has been uploaded, a receiver's refusal of the finalize can reach the agent as a `401`. `AuthenticatedPlatformHTTPClient` treats every second `401` as a rejected device credential and calls `authorizationWasRejected`, which deletes the Keychain record and puts the agent in re-pairing-required state. A `401` that is not Platform's own authentication verdict must never cost the pairing (XR-021 CONTRACTS.md section R3-03 rule 4). A `403` on the archive routes is a permanent refusal that today is classified `unavailable` and retried forever (the same defect as the R2-19 `413`).

## What Changes

- A `401` counts as a rejected credential only when its body is an `ErrorEnvelope` whose `code` is `platform.auth.unauthenticated`. Any other `401`, including one with an empty or malformed body, still gets the single refresh retry, but is then returned to the caller as `unavailable` and never calls `authorizationWasRejected`. The same rule applies where `BackendImportPolling` and the pairing/session transport map a `401` to `refused`.
- **Deliberate break:** a non-Platform `401` no longer removes the pairing, and a `401` without a Platform envelope is no longer `refused`.
- HTTP `403` from any archive operation route maps to a new `PlatformDeviceTransportError.refusedPermanently`, so the queue stops automatic retry and shows the entry as needing attention.
- **Deliberate break:** a `403` is now a permanent failure instead of a retried `unavailable`.
- README states which responses cost the pairing and which stop an upload.

## Capabilities

### Modified Capabilities

- `durable-offline-upload-queue`: a Platform `403` is a permanent failure; only Platform's own `401` costs the device pairing.

## Impact

- Affects `AgentCore` only: `AuthenticatedPlatformHTTPClient`, the archive operation transport status mapping, `BackendImportPolling`, `URLSessionPlatformDeviceTransport`, plus documentation.
- Cites XR-021 CONTRACTS.md section R3-03 rule 4. No contracts pin and no wire shape change. The 2 GiB default and the permanent-413 rule, the Keychain store, and the resumable-upload protocol are out of scope.
