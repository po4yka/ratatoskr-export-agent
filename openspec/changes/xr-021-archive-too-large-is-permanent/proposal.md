## Why

Platform will answer HTTP 413 with a `payload_too_large` error envelope when a declared archive exceeds its configured ceiling (XR-021 CONTRACTS.md section S06 D5). `PlatformArchiveHTTPTransport` maps every status other than 401 to `PlatformDeviceTransportError.unavailable`, which the upload queue treats as retryable, so an archive that can never be accepted is rescheduled with backoff forever. A 413 is a permanent condition and must stop automatic retry and surface as an upload that needs attention.

## What Changes

- Map HTTP 413 from any archive operation route (prepare, open, status, chunk, finalize) to a new `PlatformDeviceTransportError.payloadTooLarge` instead of `unavailable`.
- The existing queue classification already sends every non-retryable error to `control = .failed`; the change adds the test that proves a 413 reaches that state at prepare and at a chunk `PUT`, and that the menu projection reports the failed entry.
- Document that the agent's default `maxArchiveBytes` stays at 2 GiB, equal to Platform's default archive ceiling.

## Capabilities

### Modified Capabilities

- `durable-offline-upload-queue`: a Platform payload-too-large refusal is a permanent failure that stops automatic retry.

## Impact

- Affects `AgentCore` only: `PlatformDeviceTransportError` and the archive operation transport status mapping, plus documentation of the default size ceiling.
- No contracts pin, no Platform change, no configuration schema change. The wider HTTP status mapping (404 and expired-session reopening, 409, `Retry-After`, other 4xx), per-request `URLSession` leaks, and anything in Platform or the importers stay out of scope.
