## MODIFIED Requirements

### Requirement: Notification permission is an authoritative gate
The agent SHALL query its notification authorization before any terminal import or watched-item reminder delivery and SHALL not request, send, or record a delivered notice when authorization is denied or unavailable.

#### Scenario: Notification service is unavailable
- **WHEN** a terminal backend import result is observed while notification authorization cannot be determined
- **THEN** the import status remains durable and no notification is claimed as delivered

#### Scenario: Reminder permission is denied
- **WHEN** watched work meets its reminder threshold while notification authorization is denied
- **THEN** the reminder remains undelivered and no delivery is recorded

### Requirement: Notification text is status-only
Every terminal import or watched-item reminder notification SHALL identify only the generic outcome or required local action. It SHALL contain no provider, archive identifier, filename, folder name, path, content, counts, report reference, hash, URL, or backend diagnostic.

#### Scenario: Partial import notification remains private
- **WHEN** an imported-with-gaps result is notified
- **THEN** the delivered title and body describe only that an import needs attention

#### Scenario: Watched-item reminder remains private
- **WHEN** an old unprocessed watched item causes a reminder
- **THEN** the delivered title and body say only that watched items need attention
