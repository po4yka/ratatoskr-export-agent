## Purpose

Defines the single durable application runtime that turns the existing Export Agent components into an observable, lifecycle-aware product.

## ADDED Requirements

### Requirement: One shared operational runtime
The application SHALL start at most one operational runtime that owns watching, candidate processing, upload scheduling, operation polling, reminders, notifications, diagnostics, and user actions.

#### Scenario: Normal launch starts the product once
- **WHEN** the application finishes a normal launch
- **THEN** one shared runtime starts every operational component once and all user surfaces observe that runtime

### Requirement: Lifecycle reconciliation is bounded and durable
The runtime SHALL checkpoint cancellation before termination and coalesce startup, wake, and network recovery into bounded reconciliation without duplicating in-flight archive work.

#### Scenario: Wake and network recovery do not duplicate work
- **WHEN** wake and network recovery signals arrive while an archive is already in flight
- **THEN** one reconciliation resumes the durable entry without creating a second operation or upload

### Requirement: Complete local-to-terminal flow
The runtime SHALL take stable ChatGPT and Claude candidates through bounded classification, immutable preservation, durable queueing, resumable upload, operation polling, privacy-safe terminal presentation, and duplicate suppression.

#### Scenario: Two providers complete independently
- **WHEN** stable synthetic ChatGPT and Claude archives appear in an authorized folder
- **THEN** each archive follows its own provider route to a truthful terminal result and replay creates no duplicate import
