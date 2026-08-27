## Purpose

Warns a user gently when work visible in an approved watched folder has remained unprocessed long enough to need attention.

## ADDED Requirements

### Requirement: Reminder eligibility is threshold-based
The agent SHALL consider an enabled watched folder eligible for a reminder only when it contains at least one observed unprocessed item whose age meets or exceeds the configured positive threshold. Disabled folders, processed items, and items younger than the threshold MUST NOT make a folder eligible.

#### Scenario: Old unprocessed item becomes eligible
- **WHEN** an enabled watched folder contains an unprocessed item whose observed age equals the configured threshold
- **THEN** the reminder policy reports that folder as eligible

#### Scenario: Recent or completed work stays quiet
- **WHEN** every item in an enabled watched folder is either processed or younger than the configured threshold
- **THEN** the reminder policy reports that folder as ineligible

### Requirement: Continuing stale work does not nag
The agent SHALL deliver at most one reminder for one continuing folder-level stale-work condition. It SHALL suppress delivery while notification permission is unavailable, while the user-selected snooze is active, and after delivery until the folder has no eligible unprocessed items.

#### Scenario: Delivered condition is suppressed
- **WHEN** a reminder was delivered for a folder and the same folder still contains eligible unprocessed items
- **THEN** another evaluation does not request a second reminder

#### Scenario: Cleared condition rearms reminders
- **WHEN** a previously reminded folder has no eligible unprocessed items and later develops a new eligible condition
- **THEN** the new condition can produce one reminder

### Requirement: Reminder text is private and actionable
The reminder SHALL say only that watched items need attention and SHALL offer opening local status. It MUST NOT reveal a folder name, file name, path, provider, archive identifier, digest, URL, content, or item count.

#### Scenario: Eligible folder produces generic text
- **WHEN** an eligible folder is presented as a local reminder
- **THEN** the title and body contain only generic watched-item attention guidance
