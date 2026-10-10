## 1. Payload-too-large is a permanent failure

- [x] 1.1 Add `Tests/AgentCoreTests/PlatformArchiveTooLargeTests.swift::testPrepareTooLargeStopsAutomaticRetry` and `::testChunkTooLargeStopsAutomaticRetry`, using the `ResumableURLProtocol` harness with a 413 `payload_too_large` envelope at `POST /v1/ai-archives/chatgpt` and at the chunk `PUT`; assert the checkpoint `control == .failed`, `nextRetryAt == nil`, the queue status counts one failed upload, and a later run makes no request. Run them and confirm they fail because the 413 is mapped to `unavailable` and the queue schedules a retry.
- [x] 1.2 Add `PlatformDeviceTransportError.payloadTooLarge` with a description and map status 413 to it in `HTTPURLResponse.transportError` of `URLSessionPlatformArchiveOperationTransport.swift`; rerun both tests and confirm they pass with no queue change.

## 2. Documentation of the size ceiling

- [x] 2.1 State in the `maxArchiveBytes` doc comment of `AgentConfiguration.swift` and in `README.md` that the 2 GiB default equals Platform's default archive ceiling and that a 413 stops automatic retry. This is documentation and cannot start from a failing test.

## 3. Gate

- [x] 3.1 Run `swift build`, `swift test`, `swift build -c release`, the release `--smoke` launch, `Tests/Distribution/run.sh`, `swiftlint`, and `openspec validate --all --strict`; all pass. A gate run is not a behaviour and cannot start from a failing test.
