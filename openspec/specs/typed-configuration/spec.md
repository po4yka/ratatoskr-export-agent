# typed-configuration Specification

## Purpose
Defines how the agent loads, validates, and defaults its local configuration file so startup is predictable, safe, and free of silent misconfiguration.

## Requirements

### Requirement: Missing configuration yields defaults
Loading the configuration SHALL succeed with the documented default configuration when the file does not exist at the configured location. The defaults SHALL leave the backend endpoint unset and the watched-folder list empty.

#### Scenario: Startup without a configuration file
- **WHEN** the configuration file is absent
- **THEN** loading succeeds and returns the default configuration with no backend endpoint and no watched folders

### Requirement: Schema version 1 only
The configuration SHALL declare `schemaVersion` equal to 1. Loading SHALL fail for a missing or different version without attempting any compatibility mapping.

#### Scenario: Unsupported schema version
- **WHEN** the configuration declares a version other than 1
- **THEN** loading fails with an error stating that only schema version 1 is supported

#### Scenario: Missing schema version
- **WHEN** the configuration omits `schemaVersion`
- **THEN** loading fails with a version error

### Requirement: Unknown fields are rejected
Decoding SHALL fail when the configuration contains any field outside schema version 1, so stale or misspelled keys cannot be silently ignored.

#### Scenario: Unrecognized field
- **WHEN** the configuration contains a field that is not part of schema version 1
- **THEN** loading fails and reports the unknown field name

### Requirement: Backend endpoint scheme restriction
`backendBaseURL`, when present, SHALL use https. Plain http SHALL be accepted only for loopback hosts (localhost, 127.0.0.1, ::1).

#### Scenario: Https endpoint accepted
- **WHEN** `backendBaseURL` is an https URL
- **THEN** loading succeeds

#### Scenario: Plain http to a public host rejected
- **WHEN** `backendBaseURL` is an http URL pointing at a non-loopback host
- **THEN** loading fails and identifies the insecure endpoint

#### Scenario: Plain http to loopback accepted
- **WHEN** `backendBaseURL` is an http URL pointing at localhost, 127.0.0.1, or ::1
- **THEN** loading succeeds

### Requirement: Archive store budget defaults when absent
When the document omits `maxArchiveStoreBytes`, loading SHALL apply the documented default archive-store budget so the immutable local store is bounded out of the box.

#### Scenario: Missing store budget field
- **WHEN** a valid version-1 document contains no `maxArchiveStoreBytes`
- **THEN** loading succeeds and the loaded configuration carries the documented default store budget

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

### Requirement: Watched folder entries are usable
Every `watchedFolders` entry SHALL be a non-empty string; loading SHALL fail on an empty entry.

#### Scenario: Empty watched folder entry
- **WHEN** `watchedFolders` contains an empty string
- **THEN** loading fails and reports the offending entry

### Requirement: Errors identify file and reason without leaking contents
Validation failures SHALL produce an error that names the configuration file location and the failure reason, and SHALL NOT include the file's raw contents.

#### Scenario: Error report shape
- **WHEN** configuration loading fails validation
- **THEN** the reported error names the configuration file path and the reason, and contains none of the file's raw contents
