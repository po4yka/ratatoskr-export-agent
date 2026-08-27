## Purpose

Connects a preserved local export to its authoritative Platform operation without duplicating
bytes, provider parsing, or terminal import claims in the macOS agent.

## ADDED Requirements

### Requirement: The agent submits a verified archive through one Platform operation
For a locally managed ChatGPT or Claude archive with verified SHA-256 and byte length, the agent
SHALL create a provider-bound Platform operation before it transfers archive bytes. It SHALL bind
the returned operation identifier to the same durable journal entry before treating the transfer as
accepted, and SHALL stream only the managed archive copy to that operation's content URL.

#### Scenario: Platform accepts a new archive operation
- **WHEN** a queued archive with provider, digest and byte size is submitted with a valid device credential
- **THEN** the agent persists the returned operation ID and sends the managed archive bytes to the returned operation content URL

#### Scenario: A repeated submission receives the same operation
- **WHEN** Platform returns an existing idempotent operation for the archive identity
- **THEN** the agent binds that operation and does not create a second local archive or alter its verified digest evidence

### Requirement: Uncertain transfer outcomes preserve authoritative recovery
The agent SHALL retain a successfully bound operation ID when the content transfer is unavailable,
refused after an uncertain network result, or returns an invalid acknowledgement. It SHALL not
invent an upload or terminal import state; callers SHALL recover the real state through the
existing operation polling path.

#### Scenario: The content request loses connectivity after acceptance
- **WHEN** the operation was persisted but the content transfer cannot obtain a valid response
- **THEN** the journal retains that operation ID and its backend presentation remains processing until a later successful poll establishes a fact

### Requirement: Archive transport is private and bounded
The agent SHALL require an HTTPS Platform origin, attach the paired-device access credential only
to Platform requests, and send the provider, lower-case SHA-256 and exact byte size supplied by the
already verified local archive. It SHALL not inspect archive content, follow redirects, or send a
provider credential.

#### Scenario: An invalid Platform response is rejected
- **WHEN** Platform omits a valid operation ID or returns an unexpected response status
- **THEN** the submission fails without recording a fabricated operation binding
