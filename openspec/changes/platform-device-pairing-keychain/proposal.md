## Why

The export agent cannot submit archives to Platform until a user has explicitly approved this macOS installation. Platform's accepted device-credential lifecycle now provides that authority boundary; the agent needs a provider-neutral client implementation that retains its credentials only in macOS Keychain and truthfully degrades when access is revoked.

## What Changes

- Add an explicit `export_agent` pairing exchange against Platform's existing device endpoints. The agent accepts a pairing code created and approved from the user's primary session; it never initiates a provider login or treats a local device name as approval.
- Add a narrow Keychain-backed credential store and a test-only store seam. Only the agent process reads the device root secret, access credential, and refresh token; configuration and the durable journal retain non-secret identity/status metadata only.
- Add a serial credential-session coordinator that refreshes an access credential before use, commits a rotated credential set atomically, and opens a replacement session with the device root secret only after an ordinary refresh refusal.
- Add explicit unauthenticated/revoked degradation: clear unusable session credentials, preserve only the non-secret device record needed for diagnosis, stop authenticated work, and require explicit re-pairing when the device-root login is also refused.
- Add fixture-based handshake, credential-store, rotation, and revocation tests, plus privacy assertions that no credential reaches errors or logs.

## Capabilities

### New Capabilities

- `platform-device-pairing`: Pair the export agent as a Platform device, retain its credential lifecycle in Keychain, rotate credentials safely, and expose truthful re-pairing-required degradation.

### Modified Capabilities

<!-- none: this change introduces a new local client capability without modifying an existing requirement -->

## Impact

- Adds provider-neutral networking, credential-domain, Keychain adapter, and fixture transport types to `AgentCore`; the UI is limited to an observable pairing/reauthorization state and does not receive secret values.
- Uses the existing Platform `/v1/devices/pair`, `/v1/sessions/refresh`, and `/v1/sessions/device` contract defined by accepted Platform ADR-0016 and OpenAPI; no Platform, workspace-contract, or API-version change is proposed.
- Requires Security.framework on macOS for the production Keychain adapter. Tests use an injected store and run a macOS Keychain round-trip only where the CI keychain environment permits it, reporting a documented verification gap otherwise.
