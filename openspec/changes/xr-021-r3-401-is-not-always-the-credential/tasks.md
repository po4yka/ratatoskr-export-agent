## 1. Only Platform's own 401 costs the pairing

- [x] 1.1 In `Tests/AgentCoreTests/AuthenticatedPlatformTransportTests.swift` add `testA401WithoutThePlatformEnvelopeDoesNotRemoveThePairing`, `testA401WithAnEmptyBodyDoesNotRemoveThePairing` and `testA401WithTheMalformedBodyDoesNotRemoveThePairing` (second answer `401`; `authorizationWasRejected` is not called, the call throws `unavailable`, the stored credential and `.paired` status stay), plus the regression pin `testA401WithPlatformAuthUnauthenticatedStillRemovesThePairingAfterOneRefresh`; a coordinator-backed test asserts the credential store and status. Run them and confirm the first three fail on the assertion that `authorizationWasRejected` was called.
- [x] 1.2 Add `PlatformAuthVerdict`, call `authorizationWasRejected` in `AuthenticatedPlatformHTTPClient` only for the Platform envelope, map a non-Platform `401` to `unavailable` in the archive transport, `BackendImportPolling` and `URLSessionPlatformDeviceTransport`, and update the existing second-401 test to answer with Platform's envelope. Rerun and confirm all pass.

## 2. A 403 on the archive routes is permanent

- [ ] 2.1 Add `Tests/AgentCoreTests/PlatformArchiveRefusedTests.swift::testFinalizeForbiddenStopsAutomaticRetry` and `::testPrepareForbiddenStopsAutomaticRetry` using the `ResumableURLProtocol` harness with a 403 `chatgpt.account.unmapped` envelope; assert `control == .failed`, `nextRetryAt == nil`, the menu title "1 upload need attention", and no request on a later run. Run them and confirm they fail because 403 is mapped to `unavailable` and the queue schedules a retry.
- [ ] 2.2 Add `PlatformDeviceTransportError.refusedPermanently` and map 403 to it in `HTTPURLResponse.transportError`; rerun and confirm both pass with no queue change.

## 3. Documentation

- [ ] 3.1 State in `README.md` which responses cost the pairing (only Platform's own `401`) and which stop an upload (`413`, `403`). Documentation cannot start from a failing test.

## 4. Gate

- [ ] 4.1 Run `swift build`, `swift test`, `swift build -c release`, the release `--smoke` launch, `Tests/Distribution/run.sh`, `swiftlint`, and `openspec validate --all --strict`; all pass. A gate run is not a behaviour and cannot start from a failing test.
