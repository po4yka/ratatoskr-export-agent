## Context

The queue can stream bytes through a generic blob receipt transport, while the journal and polling
code already understand a Platform operation once another component supplies its ID. The Platform
archive contract now supplies a prepare request and a fixed operation content URL.

## Goals / Non-Goals

**Goals:**

- Make operation creation, durable binding and managed-copy transfer one recoverable queue action.
- Preserve local truth on every uncertain network boundary.
- Reuse the strict HTTPS/no-redirect device transport conventions already used for pairing and
  operation reads.

**Non-Goals:**

- Provider login, archive parsing, content inspection, or local deletion.
- Interpreting completeness: the existing backend status mapper remains the only reader of a
  terminal backend payload.
- Upload resumption protocol beyond Platform's idempotent operation binding; retries re-query the
  bound operation rather than manufacture a new identity.

## Decisions

### Prepare before content transfer

The transport first posts provider, digest and size, then persists the returned UUID, then uploads
the managed file to the operation-specific path. This gives a durable recovery key before any
ambiguous content request. Sending directly to a provider URL would bypass the public Platform
boundary and make uncertain results unsafe.

### Bind immediately, poll after uncertainty

Once prepare returns a well-formed operation ID, the journal records it even if content transfer
later fails. A later retry or poll works from that ID. Waiting to persist until a successful content
response would risk duplicate uploads after a lost response.

### One opaque, streaming URLSession request

The transport receives a file URL and uses a streamed request body. The agent does not decode ZIP
members or construct provider-specific payloads. Existing TLS and redirect blocking remain in the
same URLSession family.

## Risks / Trade-offs

- [Platform accepts metadata but the process ends before content starts] → the persisted operation
  remains observable and retryable; UI shows the last real processing observation.
- [An old or malicious response claims an operation ID] → accept only HTTPS, exact expected status,
  UUID-shaped ID and recognized provider; do not bind malformed responses.
- [A content response is lost after Platform received bytes] → retain the binding and poll rather
  than re-prepare a new operation.

## Migration Plan

Deploy the Platform acceptance endpoint before the agent. Roll back the agent by stopping queue
submissions; every managed archive remains locally preserved and a bound operation remains readable
through Platform. No local data migration is required.
