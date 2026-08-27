## 1. Operation preparation

- [x] 1.1 RED: add `Tests/AgentCoreTests/PlatformArchiveOperationTransportTests.swift` with `prepareBindsReturnedOperationBeforeContentTransfer`, asserting the current agent has no operation-bound submit path.
- [x] 1.2 GREEN: implement the strict HTTPS prepare response decoder and request construction; verify `prepareBindsReturnedOperationBeforeContentTransfer` passes.

## 2. Durable managed-copy submission

- [x] 2.1 Regression test: extend `Tests/AgentCoreTests/PlatformArchiveOperationTransportTests.swift` with `transferFailureRetainsBoundOperationForPolling`, asserting a transport failure does not erase the returned operation ID. This was an integration test because the pre-existing standalone submitter already bound the operation before the queue route existed.
- [x] 2.2 GREEN: connect the queue action to bind the operation before streaming the managed file and retain it after an uncertain transfer; verify `transferFailureRetainsBoundOperationForPolling` passes.

## 3. Boundary validation

- [x] 3.1 Regression test: add malformed and insecure-origin prepare cases in `Tests/AgentCoreTests/PlatformArchiveOperationTransportTests.swift`, asserting no rejected preparation can mutate the journal.
- [x] 3.2 GREEN: reject unexpected status, redirects, non-HTTPS origins and malformed operation payloads without a journal binding; verify all transport tests pass.

## 4. Validation and lifecycle

- [x] 4.1 Run `build-gate -- swift test`, `openspec validate --all --strict`, and inspect the staged diff; verify the full local gate is green.
- [x] 4.2 Archive the completed OpenSpec change and verify `openspec validate --archived` passes.
