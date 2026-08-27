## 1. Contract-backed operation projection

- [x] 1.1 RED: add `Tests/AgentCoreTests/BackendImportStatusTests.swift` fixture tests
  `testCompleteAndGapSummariesMapOnlyFromValidOperationPayloads` and
  `testFailedOperationDoesNotExposeBackendDiagnostic`; verify the canonical `ai_archive_id` fixture
  fails before the mapper recognizes the contract field.
- [x] 1.2 GREEN: implement the strict Platform operation DTO, bounded import-summary decoder, and
  status mapper; rerun `BackendImportStatusTests` and verify it passes.

## 2. Durable polling and stale truth

- [x] 2.1 RED: add `BackendImportPollingTests.testTerminalObservationRetainsItsOrderingTimestampWhenARepeatOmitsIt`;
  verify the repeat incorrectly replaces the prior observed and backend ordering timestamps.
- [x] 2.2 GREEN: persist the compact operation projection, add authenticated HTTPS operation
  polling, and retain the last valid timestamp after unavailable, invalid, stale, or timestamp-less
  reads; rerun the focused polling tests and verify they pass.

## 3. Permission-gated terminal notifications

- [x] 3.1 RED: add `ImportNotificationTests.testConcurrentAuthorizedChecksDeliverOnlyOneTerminalNotice`;
  verify two concurrent terminal checks reach the notification service before the delivery marker.
- [x] 3.2 GREEN: implement the authorization-gated notification coordinator, in-flight delivery
  reservation, and macOS adapter;
  rerun `ImportNotificationTests` and verify they pass.

## 4. Safe UI projection

- [x] 4.1 RED: add `Tests/RatatoskrExportAgentTests/ImportStatusMenuTests.swift` tests for a
  complete result, a gaps result, and last-known unavailable rendering; verify they fail because
  the menu projection does not exist.
- [x] 4.2 GREEN: render durable per-archive import status in the menu with generic text, a short
  local id, and last-known timestamp only; rerun `ImportStatusMenuTests` and verify they pass.

## 5. Documentation and full validation

- [x] 5.1 Update README and DEVELOPMENT.md with the operation-status/notification boundary and
  contract dependency; documentation task has no failing test. Verify the stated checks and
  implementation status are accurate.
- [x] 5.2 Run `openspec validate --all --strict`, `openspec validate --archived`, and the complete
  DEVELOPMENT.md command list through the required build gate; verify each observed result.
