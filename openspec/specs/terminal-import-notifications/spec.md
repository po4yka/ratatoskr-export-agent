# terminal-import-notifications Specification

## Purpose
Presents terminal archive import outcomes through local notifications without revealing sensitive
export data or bypassing the user's operating-system permission decision.

## Requirements

### Requirement: Notification permission is an authoritative gate
The agent SHALL query its notification authorization before delivery and SHALL not request, send,
or record a delivered notice when authorization is denied or unavailable.

#### Scenario: Notification service is unavailable
- **WHEN** a terminal backend import result is observed while notification authorization cannot be
  determined
- **THEN** the import status remains durable and no notification is claimed as delivered

### Requirement: Notification text is status-only
Every terminal import notification SHALL identify only the generic outcome: complete, needs
attention, or failed. It SHALL contain no provider, archive identifier, filename, path, content,
counts, report reference, hash, or backend diagnostic.

#### Scenario: Partial import notification remains private
- **WHEN** an imported-with-gaps result is notified
- **THEN** the delivered title and body describe only that an import needs attention
