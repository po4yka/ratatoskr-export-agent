## Purpose

Decides when a file seen in an inbox is a finished, safe download. A half-written archive must never be queued: ingestion of incomplete bytes corrupts the backup downstream. Detection relies on quiet-period evidence plus exclusion rules, never on a single notification.

## ADDED Requirements

### Requirement: Stability requires an unchanged size and modification time across a quiet interval

A candidate SHALL be queued as stable only after its byte size and modification time remain identical across one full configured quiet interval, measured from the system's own first observation of the path.

#### Scenario: Quiet file crosses the stability threshold

WHEN a fixture file is written once and its observed size and modification time stay unchanged across the whole quiet interval
THEN the file is queued as stable with evidence naming the quiet duration.

#### Scenario: File observed briefly stays pending

WHEN the same fixture file has been observed unchanged for less than the quiet interval
THEN the file remains pending and is not queued.

### Requirement: Any observed change restarts the quiet clock

While a candidate's size or modification time changes between observations, the candidate SHALL stay pending, and the quiet interval SHALL restart from the latest change.

#### Scenario: Growing download never queues

WHEN a fixture file's size grows across successive simulated writes
THEN the file stays pending throughout and is not queued while it grows.

#### Scenario: Touch without growth keeps the clock reset

WHEN the size stops growing but the modification time keeps changing
THEN the file stays pending until both values hold still for the full interval.

### Requirement: A detected writer hold blocks queueing

Where the platform permits detecting that another process holds the file open for writing, a candidate with a detected writer hold SHALL remain pending even while its size and modification time look quiet.

#### Scenario: Held file stays pending despite quiet metadata

WHEN the writer-hold probe reports an active writer for an otherwise quiet fixture file
THEN the file remains pending and is not queued.

#### Scenario: Probe passes and quiet file queues

WHEN the writer-hold probe passes for a file whose size and modification time have been quiet for the interval
THEN the file is queued as stable.

### Requirement: Temporary download suffixes are excluded

A path carrying a known temporary download suffix (such as .download, .crdownload, .part, or .partial) SHALL never be queued regardless of its stability evidence; once renamed to a name without such a suffix it becomes eligible as a fresh candidate.

#### Scenario: Suffixed partial is never queued

WHEN a fixture file named with a temporary download suffix shows fully quiet metadata beyond the interval
THEN the file is not queued.

#### Scenario: Rename to final name makes the file eligible

WHEN the same content is renamed to a name without a temporary suffix
THEN the file becomes eligible and is queued only after passing the stability requirements from its first observation under the final name.

### Requirement: Only regular readable files within the size ceiling are eligible

The system SHALL reject candidates that are not regular files (directories, symlinks, devices, other special files), candidates that cannot be read, and candidates whose size exceeds the configured ceiling, recording the rejection reason in place of a queue entry.

#### Scenario: Non-regular file is rejected

WHEN the discovered path resolves to a symlink or a directory
THEN the path is rejected as not being a regular file and is never queued.

#### Scenario: Oversized file is rejected immediately

WHEN a fixture file's size exceeds the configured ceiling
THEN the file is rejected with the size-limit reason without waiting for stability.

#### Scenario: Unreadable file is rejected

WHEN the file's contents cannot be read by the agent
THEN the file is rejected with the unreadable reason instead of being queued.
