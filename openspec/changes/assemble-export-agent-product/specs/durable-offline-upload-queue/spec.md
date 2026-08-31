## ADDED Requirements

### Requirement: Mixed-provider controls remain per entry
Retry, pause, cancel, and recovery SHALL operate on one journal entry and SHALL use that entry's immutable provider and operation checkpoint.

#### Scenario: One provider failure does not reroute another
- **WHEN** a Claude transfer is paused while a ChatGPT transfer remains eligible
- **THEN** the Claude entry stays bound to Claude and the ChatGPT entry proceeds on its own route
