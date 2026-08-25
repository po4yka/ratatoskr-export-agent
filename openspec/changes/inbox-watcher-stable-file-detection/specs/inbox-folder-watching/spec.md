## Purpose

Observes the enabled watched folders so that files appearing in an inbox become candidates for import regardless of how the user's browser delivers them. Observation is hint-driven and debounced; losing one folder degrades only that folder.

## ADDED Requirements

### Requirement: Watching follows the enabled registered folders

The system SHALL observe exactly the enabled registered folders resolved to their current locations when watching starts, and SHALL NOT observe disabled or unregistered locations.

#### Scenario: Start observes enabled folders only

WHEN watching starts with one enabled and one disabled registered folder
THEN events and candidates arise only from the enabled folder's directory.

### Requirement: Event bursts collapse into one debounced scan

Filesystem notifications are hints, not commands. The system SHALL coalesce notifications arriving within a bounded debounce window into a single directory scan, and a notification arriving after a completed scan SHALL trigger a further scan.

#### Scenario: Burst of events produces one scan

WHEN several filesystem notifications for a folder arrive inside one debounce window
THEN exactly one scan of that folder covers the whole burst once the window closes.

#### Scenario: Late event triggers another scan

WHEN a notification arrives after the previous scan has run
THEN a new debounced scan is scheduled and runs.

### Requirement: Discovery includes files already present

The system SHALL perform a scan of each watched folder when watching starts, so files present before the agent started are discovered like newly arrived ones.

#### Scenario: Pre-existing file is discovered at start

WHEN watching starts on a folder that already contains a regular file
THEN that file is discovered as a candidate without any further filesystem notification.

### Requirement: Repeated notifications are idempotent

Repeated notifications about the same path SHALL NOT create duplicate candidates: a path under evaluation remains one candidate until it reaches a terminal local outcome.

#### Scenario: Duplicate events keep one candidate

WHEN the same inbox path is notified repeatedly while it is being evaluated
THEN the path is tracked as a single candidate with one eventual outcome.

### Requirement: A vanished folder degrades alone

When a watched folder disappears or cannot be read while watching, the system SHALL report that folder as degraded with the reason, SHALL stop emitting candidates for it, and SHALL continue observing every other watched folder unaffected.

#### Scenario: Deleted folder degrades without stopping others

WHEN a watched folder's directory is removed while two folders are being watched
THEN the removed folder is reported degraded and the other folder continues to produce candidates.

### Requirement: Stopping ends observation cleanly

Stopping watching SHALL cease all scans and candidate emissions, SHALL be safe to call more than once, and SHALL leave no observation active afterwards.

#### Scenario: Stop halts all activity

WHEN watching stops and further filesystem notifications occur afterwards
THEN no scan runs and no further candidate is emitted.
