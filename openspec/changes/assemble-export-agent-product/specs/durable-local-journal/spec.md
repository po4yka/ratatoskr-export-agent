## ADDED Requirements

### Requirement: Archive route is an immutable per-entry fact
Every version-1 journal entry SHALL durably retain its ChatGPT or Claude route, bounded classification evidence, source policy, operation identity, transfer checkpoint, retry control, and last backend observation, and SHALL reject transitions that alter those identity facts.

#### Scenario: Mixed providers survive reopen
- **WHEN** ChatGPT and Claude entries are written and the journal is reopened
- **THEN** each entry retains its distinct route, classification, policy, operation, and processing state

#### Scenario: Incompatible development journal fails closed
- **WHEN** a journal record predating the required per-entry route is opened
- **THEN** the journal refuses the document without modifying the journal or any managed archive
