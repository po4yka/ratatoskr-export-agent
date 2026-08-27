## MODIFIED Requirements

### Requirement: Budgets are present and positive
`maxArchiveBytes` SHALL be greater than zero, `maxConcurrentUploads` SHALL be at least one, and `maxArchiveStoreBytes`, when present, SHALL be greater than zero; otherwise loading SHALL fail naming the offending budget. The version-1 document SHALL also require positive `uploadChunkBytes` and `maxUploadBytesPerSecond` values that lie within documented protocol and local safety bounds.

#### Scenario: Non-positive byte budget rejected
- **WHEN** `maxArchiveBytes` is zero or negative
- **THEN** loading fails and names `maxArchiveBytes`

#### Scenario: Zero upload concurrency rejected
- **WHEN** `maxConcurrentUploads` is less than one
- **THEN** loading fails and names `maxConcurrentUploads`

#### Scenario: Non-positive store budget rejected
- **WHEN** `maxArchiveStoreBytes` is present and zero or negative
- **THEN** loading fails and names `maxArchiveStoreBytes`

#### Scenario: Invalid transfer cap rejected
- **WHEN** `uploadChunkBytes` or `maxUploadBytesPerSecond` is zero, negative, or outside its documented bound
- **THEN** loading fails and names the offending transfer field
