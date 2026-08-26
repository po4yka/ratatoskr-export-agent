## Purpose

Defines how the agent loads, validates, and defaults its local configuration file so startup is predictable, safe, and free of silent misconfiguration.

## ADDED Requirements

### Requirement: Archive store budget defaults when absent

When the document omits `maxArchiveStoreBytes`, loading SHALL apply the documented default archive-store budget so the immutable local store is bounded out of the box.

#### Scenario: Missing store budget field

- **WHEN** a valid version-1 document contains no `maxArchiveStoreBytes`
- **THEN** loading succeeds and the loaded configuration carries the documented default store budget

## MODIFIED Requirements

### Requirement: Budgets are present and positive
`maxArchiveBytes` SHALL be greater than zero, `maxConcurrentUploads` SHALL be at least one, and `maxArchiveStoreBytes`, when present, SHALL be greater than zero; otherwise loading SHALL fail naming the offending budget.

#### Scenario: Non-positive byte budget rejected
- **WHEN** `maxArchiveBytes` is zero or negative
- **THEN** loading fails and names `maxArchiveBytes`

#### Scenario: Zero upload concurrency rejected
- **WHEN** `maxConcurrentUploads` is less than one
- **THEN** loading fails and names `maxConcurrentUploads`

#### Scenario: Non-positive store budget rejected
- **WHEN** `maxArchiveStoreBytes` is present and zero or negative
- **THEN** loading fails and names `maxArchiveStoreBytes`
