## Context

See proposal.md and the workspace `ai-archive-operation-summary` change. The journal already owns
archive identity and durable upload state, while the existing menu only renders an aggregate upload
projection. Platform operation snapshots are the sole backend authority.

## Goals / Non-Goals

**Goals:**

- Keep a journal-backed import-operation projection across restart.
- Decode a constrained operation payload and expose an aggregate-safe per-archive presentation.
- Make network failure visibly stale rather than semantically successful.
- Deliver one generic local notice for a newly observed terminal result only with permission.

**Non-Goals:**

- Accepting imports, deep-parsing archives, querying provider services, or interpreting backend
  errors/gap detail.
- Requesting notification permission, including private fields in a menu or notification, or
  adding a second persisted store.

## Decisions

- A protocol abstracts authenticated operation reads; its URLSession implementation reads only
  `GET /v1/operations/{id}` from the paired Platform origin and maps transport errors to
  unavailable. This keeps authentication, TLS validation, and redirect blocking on the existing
  Platform boundary.
- A strict DTO decoder recognizes only the workspace summary extension and maps operation status
  plus completeness classification to the agent's closed presentation model. Missing/malformed
  summaries are unverified, not imported.
- The journal stores a compact projection, last-observed time, and notification identity. Backend
  error text, warning text, full result extensions, paths, and content never enter the journal or
  UI model.
- UI surfaces consume that durable projection. The menu uses generic status text plus a short local
  id and last-known timestamp; it has no authority to poll or mutate archive state.
- Notification delivery is behind an injected authorization/delivery interface. The production
  adapter uses macOS local notifications, while deterministic tests use an in-memory recorder.

## Risks / Trade-offs

- [An older producer omits the summary] -> Show a terminal unverified result rather than claiming
  completeness.
- [Backend is unreachable] -> Preserve last valid observation and its timestamp; do not change the
  presentation state.
- [Operation payload evolves] -> Reject an invalid summary while retaining the last valid durable
  projection; do not fall back to heuristic filename or status mapping.

## Migration Plan

The journal's current schema definition is amended in place under the development-status rule. New
fields decode as absent for existing entries; the first valid poll supplies them. Deploy this agent
consumer after the workspace contract, then producers. Rollback leaves compact observation fields
in journal records but stops polling/notifications; no archive copy or credential is removed.
