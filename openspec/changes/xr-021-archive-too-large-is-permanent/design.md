## Context

`UploadQueue.retryCheckpoint(for:from:at:)` retries `PlatformDeviceTransportError.unavailable` and the receipt-transport retry cases and marks every other error `control = .failed`, which `isEligible` excludes from scheduling until the user retries explicitly, and which `UploadQueueStatus` counts as "need attention". The only defect is upstream of that switch: `HTTPURLResponse.transportError` in `URLSessionPlatformArchiveOperationTransport.swift` collapses every non-401 status into `unavailable`.

## Decisions

### A dedicated transport error, not a queue special case

Add `case payloadTooLarge` to `PlatformDeviceTransportError` and return it from `transportError` for status 413. The queue needs no change because its `default` branch already treats an unknown error as permanent. Classifying by status in the transport keeps the queue free of HTTP knowledge. Inspecting the `payload_too_large` envelope body was rejected: the status code alone is the contract (XR-021 CONTRACTS.md section S06 D5), and the agent must not depend on a body shape for a permanent decision.

### The size ceiling stays 2 GiB

`AgentConfiguration.defaultValue.maxArchiveBytes` already equals Platform's default `archive_staging.max_archive_bytes` (2147483648), and the local candidate gate rejects larger files before upload. No value changes; the doc comment and README state the equality so a future change to either side is made knowingly.

## Risks

- A Platform deployment with a ceiling below the agent's configured `maxArchiveBytes` now produces a failed entry instead of an endless retry loop; the user must lower `maxArchiveBytes` or raise the Platform ceiling and retry manually.
