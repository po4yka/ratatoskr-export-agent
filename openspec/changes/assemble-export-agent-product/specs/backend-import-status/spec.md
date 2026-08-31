## ADDED Requirements

### Requirement: Product surfaces share truthful operation state
The menu, history, diagnostics, and notifications SHALL derive from the shared durable runtime and SHALL expose only privacy-safe last-known and terminal operation facts.

#### Scenario: Terminal result reaches every surface
- **WHEN** Platform returns a valid terminal import summary
- **THEN** menu and history show the terminal state, diagnostics reflect the queue, and at most one generic notification is delivered
