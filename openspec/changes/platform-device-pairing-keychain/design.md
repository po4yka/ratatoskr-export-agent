## Context

See `proposal.md` for motivation and `specs/platform-device-pairing/spec.md` for the behavior contract. `AgentCore` already has the configuration, redacting log, immutable archive, and durable journal foundations but no HTTP or credential layer. Platform's accepted device lifecycle is defined by `repos/platform/docs/adr/0016-device-credential-model.md` and its checked-in OpenAPI document; this client change consumes that contract without changing it.

The agent must retain a per-device root secret, short-lived bearer credential, and rotating refresh token, yet configuration and journal files are not secret stores. Pairing and recovery need deterministic fixture tests without a live Platform or a test user's Keychain entries.

## Goals / Non-Goals

**Goals:**

- Make Platform credential ownership explicit in a small agent-core boundary with safe test doubles.
- Bind one credential record to one normalized HTTPS origin and Platform-issued device UUID.
- Ensure refresh serialization and durable replacement of a credential pair before it is reused.
- Make revocation a finite, observable local state rather than an upload retry loop.

**Non-Goals:**

- Creating pairing codes, primary-session authentication, QR rendering, device/session listing, or remote revocation UI.
- Upload, operation tracking, offline queue, browser automation, provider authentication, or any Platform contract change.
- A separate background helper, Keychain access-group entitlement, or distribution signing work; those belong to the distribution milestone. This change nevertheless keeps secret access confined behind the agent credential boundary.

## Decisions

### D1: Consume the established three-endpoint lifecycle

`PlatformDeviceTransport` will issue JSON requests only to `/v1/devices/pair`, `/v1/sessions/refresh`, and `/v1/sessions/device` on an explicitly configured HTTPS origin. Pairing sends kind `export_agent`; its code comes from the user after primary-session approval. The implementation will decode only the published success fields and a small typed classification of refusal, validation, transport, and server errors.

The alternative of minting a device claim locally or adding an export-agent-specific endpoint is rejected: it would bypass the primary-session approval and requires a cross-repository contract change. The alternative of accepting redirects is rejected because credentials must never cross origins.

### D2: Separate public pairing metadata from a single opaque secret record

`PairedDeviceIdentity` holds the normalized origin, device UUID, user UUID, and expiry/status values and may be persisted in the journal or settings. `DeviceCredentialSet` holds the root secret, bearer credential, and refresh token. A `DeviceCredentialStoring` protocol accepts and returns the latter only for a supplied identity; it has an in-memory test implementation and a macOS implementation backed by one Keychain generic-password item per origin/device.

The Keychain item will use a stable service name, a non-secret derived account identifier, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, and no synchronizable attribute. It is a single encoded value so new session credentials replace together. Callers receive typed failures without `OSStatus` context that could include sensitive data. The alternative of putting encrypted bytes in the journal/configuration is rejected because encryption-key lifecycle would recreate a weaker secret store and violate the product boundary.

### D3: Serialize all credential mutation in one actor

`DeviceSessionCoordinator` owns reads and writes to the credential store. It pairs only after a complete successful response; it writes the complete Keychain record before publishing paired state. For a refresh it sends the current token once, writes the returned credential/access-expiry pair as a unit, then returns the access credential. Concurrent callers await the same actor rather than replaying a consumed refresh token.

On a normal refresh refusal, the coordinator makes one `/v1/sessions/device` request using the root secret and atomically saves its returned session pair. It does not retry a refresh token or race more than one recovery request. A full restart can read the stored set and use the same coordinator path. Per-request independent refresh logic is rejected because Platform treats replay as compromise and revokes the session family.

### D4: Represent lost authorization as a non-secret terminal local state

If refresh and root-secret recovery are both refused, the coordinator deletes the Keychain record, retains only `PairedDeviceIdentity` and status `.rePairingRequired`, and rejects future authenticated work until a user pairs again. It does not delete archives, journal entries, or folder access records. The caller receives a safe action-required error suitable for UI and queue logic; no credential-containing network payload or response is passed to logging.

Keeping stale session credentials for repeated background retries is rejected because it risks replay and turns a user action requirement into unbounded traffic. Silently treating a 401 as a successful upload is rejected because it would misstate backup completeness.

### D5: Fixture transport plus an opt-in Keychain integration test

Unit tests drive protocol fixtures for exact request paths/bodies, one-time secrets, rotation, root-session recovery, and revocation. Tests name concrete fake tokens only inside their process and assert that output/log representations omit them. The production Keychain adapter gets a round-trip/delete integration test gated by an explicit environment capability; if unavailable in CI, the test emits a documented skipped-evidence reason while all protocol behavior remains covered by the in-memory store.

Using a live Platform fixture is rejected for this change: device pairing consumes single-use credentials and would require an authenticated primary session. Using config-file fixtures for secret persistence is rejected because it normalizes the forbidden storage path.

## Risks / Trade-offs

- [A Keychain service can be unavailable in headless CI] → Keep deterministic storage-contract tests injected and make the real Keychain round-trip conditional with an explicit, visible verification record; run it on a macOS signed-app test environment before distribution.
- [A crash occurs between accepting a one-time pair response and storing it] → Do not publish identity until Keychain storage succeeds; the user can create a fresh pairing code and remove any orphaned Platform device through their primary session.
- [A crash occurs while persisting rotation] → Store one encoded credential set in one Keychain replace operation and serialize all mutations; a failed write leaves authentication unavailable rather than falling back to an already-spent token.
- [An unsigned development build cannot prove final code-signing isolation] → Limit this change to Keychain confinement and agent-only API ownership; validate access-group/sandbox policy with the later signing-and-entitlements work before shipping a distributed app.
- [Platform returns an unknown 4xx/5xx shape] → Treat it as a safe typed failure without printing response bodies and do not clear credentials unless the established unauthenticated recovery sequence proves authorization loss.

## Migration Plan

This is additive. A clean install begins unpaired; existing local archives, journal records, and folder bookmarks remain untouched. The first successful pairing creates an origin/device-bound Keychain item and non-secret identity metadata. Rollback removes the new executable code; it never deletes a user's archive or a Keychain credential automatically. A user can remove the Keychain item through an explicit future unpair action or macOS Keychain management.

## Open Questions

None blocking. The signed distribution's Keychain access-group entitlement is deliberately deferred to plan item 10 and does not change the pairing protocol or this task breakdown.
