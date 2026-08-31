## 1. Durable mixed-provider routing

- [x] 1.1 RED — add `MixedProviderJournalRoutingTests.swift` proving ChatGPT and Claude route, classification, policy, operation and transfer state survive reopen, and incompatible old development records leave managed archives untouched.
- [x] 1.2 GREEN — make route/classification/policy required immutable per-entry version-1 journal facts, separate operation transfer from terminal observation, remove queue-wide routing, and make 1.1 pass.

## 2. Same-operation authenticated transfer

- [x] 2.1 RED — add `PlatformResumableArchiveHTTPTransportTests.interruption_relaunch_resumes_same_operation` covering one prepare, status recovery, missing chunks, and finalization after journal/transport recreation.
- [x] 2.2 GREEN — implement operation-bound open/chunk/status/finalize, durable pre-presentation checkpoints and same-operation queue recovery; make 2.1 pass.
- [x] 2.3 RED — add request authorization tests proving every transfer request and operation poll obtains current authority, rotation changes later requests, one 401 recovers, and revocation preserves local work.
- [x] 2.4 GREEN — route authenticated requests through the shared session coordinator with strict HTTPS/no redirects and bounded 401 recovery; make 2.3 pass.

## 3. Onboarding and runtime composition

- [x] 3.1 RED — add `PairingOnboardingTests.relaunch_restores_non_secret_identity_and_keychain_session` covering endpoint, pair, relaunch, refresh, revoke, re-pair and launch-at-login state without visible secrets.
- [x] 3.2 GREEN — persist HTTPS origin/non-secret identity, add onboarding actions and `SMAppService.mainApp`, keep Keychain as the sole secret store, and make 3.1 pass.
- [x] 3.3 RED — add `RuntimeCompositionTests.normal_launch_starts_one_shared_operational_runtime` proving watcher, candidate processor, upload scheduler, poller and reminders start once and share projections.
- [x] 3.4 GREEN — add one actor-owned runtime/app delegate composition and shared menu/window bindings; make 3.3 pass while keeping smoke mode offline.
- [x] 3.5 RED — add `RuntimeCompositionTests.shutdown_sleep_wake_and_network_recovery_reconcile_without_duplicate_work`.
- [x] 3.6 GREEN — add cancellable loops, coalesced startup/wake/network reconciliation, graceful stop and user-controlled main-app login registration; make 3.5 pass.
- [x] 3.7 RED — add a vertical runtime test covering stable ChatGPT and Claude archives, immutable preservation, mixed routing, resumable upload, polling, terminal history, privacy, duplicate suppression, retry, pause and cancel.
- [x] 3.8 GREEN — connect candidate processing, store, journal, queue, polling, notifications, reminders, operations UI and diagnostics; make 3.7 pass.

## 4. Immutable release and acceptance

- [x] 4.1 RED — extend distribution workflow contract tests to require explicit version/tag/source revision, final ZIP/checksum GitHub Release assets, fail-closed conflicts, least privilege, and trust checks before publication.
- [x] 4.2 GREEN — publish the accepted artifact through a final least-privilege release job only after signing, notarization, stapling, signature, Gatekeeper, source, tag and checksum checks; make 4.1 pass without publishing.
- [x] 4.3 Add a clean-machine acceptance script/checklist and static safety test for Gatekeeper, first launch, explicit folder authorization, pairing, Keychain relaunch, interrupted resume, terminal state, manual update and rollback. No runtime RED precedes owner-authorized external evidence.

## 5. Validation

- [x] 5.1 Run every focused RED before its GREEN implementation and record the diagnosed failure.
- [x] 5.2 Run the `DEVELOPMENT.md` full gate through the machine-wide build gate where compiler-backed, plus strict and archived OpenSpec validation.
- [x] 5.3 Review the final diff for secrets, personal paths/content/digests, broad entitlements, frozen tokens, unsafe release behavior and unrelated changes.
