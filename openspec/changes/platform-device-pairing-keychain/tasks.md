# Tasks: platform-device-pairing-keychain

Each behavior lands test first. A test task declares the smallest compile-safe shell required, runs its named test red, and records the behavioral failure before its paired implementation task is checked.

## 1. Pairing contract and non-secret identity

- [x] 1.1 Add failing fixture tests in `Tests/AgentCoreTests/PlatformDevicePairingTests.swift`: `testPairingPostsExportAgentAndStoresOnlyAfter201` asserts `/v1/devices/pair` receives kind `export_agent`, a successful fixture produces non-secret identity after a complete credential-store write, and `testPairingRefusalDoesNotPersistPartialState` asserts a 401 fixture leaves the store and pairing state empty. Added compile-safe transport, identity, credential-store, and coordinator shells; `build-gate -- swift test --filter PlatformDevicePairingTests` then failed on the expected missing request, state, persistence, and refusal assertions.
- [x] 1.2 Implement the typed Platform pairing request/response boundary, HTTPS-origin validation, non-secret `PairedDeviceIdentity`, fixture transport seam, and successful/refused pairing coordinator behavior. Verified `build-gate -- swift test --filter PlatformDevicePairingTests` passes (2 tests, 0 failures).

## 2. Keychain credential confinement

- [x] 2.1 Add failing tests in `Tests/AgentCoreTests/DeviceCredentialStoreTests.swift`: `testCredentialSetRoundTripsForMatchingOriginAndDevice`, `testCredentialSetCannotBeReadThroughDifferentIdentity`, and `testStoreFailurePublishesNoPartialPairingState`; use an in-memory store fixture with fake secret strings and assert all public status/error descriptions omit those strings. Added a compile-safe store shell; `build-gate -- swift test --filter DeviceCredentialStoreTests` failed on the expected round-trip assertion while mismatch and safe failure assertions held. Follow-up `testCredentialModelsRedactSecretsWhenDescribed` failed with all six fixture secrets exposed by default descriptions before explicit redaction was added.
- [x] 2.2 Implement `DeviceCredentialStoring`, the in-memory test store, and macOS Keychain generic-password store with one origin/device-bound opaque record, non-synchronizable `AfterFirstUnlockThisDeviceOnly` access, atomic replacement, and secret-free typed errors. Add redacted descriptions for every public model containing a pairing/session secret. Verified the focused credential test suite passes with 0 failures.
- [x] 2.3 Add `testMacOSKeychainRoundTripAndDelete` to the same suite, guarded by `RATATOSKR_KEYCHAIN_INTEGRATION=1`; it writes, fresh-instance reads, and deletes a uniquely named test item without inspecting any user Keychain data. This is an environment-gated production-adapter check, so its red behavior was covered by 2.1/2.2's store contract rather than rerunning a missing adapter after it existed. Verified locally with `RATATOSKR_KEYCHAIN_INTEGRATION=1 build-gate -- swift test --filter DeviceCredentialStoreTests.testMacOSKeychainRoundTripAndDelete` (1 test, 0 failures); the opt-in skip reason remains to be documented in 5.2.

## 3. Session rotation and root-secret recovery

- [x] 3.1 Add failing fixture tests in `Tests/AgentCoreTests/DeviceSessionCoordinatorTests.swift`: `testRefreshAtomicallyReplacesBothSessionCredentials`, `testConcurrentRefreshCallersSendOneRefreshToken`, and `testRefreshRefusalOpensOneReplacementSession`. The fixture shell failed with `Device credentials are unavailable`; the subsequent revocation cases also exposed duplicate refresh presentation and missing degradation.
- [x] 3.2 Implement the actor-owned serialized refresh path, atomic credential-pair replacement, and single `/v1/sessions/device` recovery after an ordinary refresh refusal. Verified `build-gate -- swift test --filter DeviceSessionCoordinatorTests` passes (6 tests, 0 failures).

## 4. Revocation and safe local degradation

- [x] 4.1 Add failing tests in `Tests/AgentCoreTests/DeviceSessionCoordinatorTests.swift`: `testDoubleUnauthenticatedResponseClearsCredentialsAndRequiresRepairing`, `testRePairingRequiredDoesNotRetryAuthenticatedTransport`, and `testRevocationStatusAndLogOutputContainNoFixtureSecrets`. The fixture failed while retaining paired status/credentials and repeated refresh transport after dual refusal.
- [x] 4.2 Implement terminal `.rePairingRequired` degradation: delete the Keychain credential record, retain only non-secret identity/status, reject future authenticated work without a network retry loop, and pass safe action-required errors to callers. Verified `build-gate -- swift test --filter DeviceSessionCoordinatorTests` passes (6 tests, 0 failures).

## 5. User-facing status and evidence

- [x] 5.1 Add failing `Tests/RatatoskrExportAgentTests/DevicePairingStatusTests.swift` coverage that a paired state shows only origin/device label/expiry and a revoked state directs the user to pair again without emitting secret fields; used a compile-safe view-model shell and observed `build-gate -- swift test --filter DevicePairingStatusTests` fail on the expected status and safe-detail assertions.
- [x] 5.2 Implement the minimal app-facing pairing/reauthorization status projection and update `README.md` plus `DEVELOPMENT.md` with the approved-code flow, Keychain boundary, revocation behavior, and the exact Keychain-integration-test evidence rule. Verified the focused app test passes (2 tests, 0 failures) and targeted SwiftLint reports 0 violations.

## 6. Full gate and delivery

- [x] 6.1 Run the full local gate: `build-gate -- swift build`, `build-gate -- swift test`, `build-gate -- swift build -c release`, `.build/release/RatatoskrExportAgent --smoke`, `swiftlint`, `npx --yes @fission-ai/openspec@1.10.0 validate --all --strict`, and `npx --yes @fission-ai/openspec@1.10.0 validate --archived`. Observed debug/release builds and smoke exit 0, 123 tests / 0 failures / 1 expected opt-in Keychain skip, SwiftLint 0 violations, strict validation 10/0, archived validation 3/0. The real Keychain round trip separately passed locally with `RATATOSKR_KEYCHAIN_INTEGRATION=1` (1 test, 0 failures); `DEVELOPMENT.md` records the CI skip evidence rule.
- [ ] 6.2 Commit only this change on `task/export-agent-device-pairing`; integrate it into local `main`, push `origin main`, verify the remote main contains the integration commit, then remove this task worktree and delete its task branch. This delivery task begins only after 6.1 is fully green; verify with `git status`, `git log origin/main`, `git worktree list`, and `git branch`.
