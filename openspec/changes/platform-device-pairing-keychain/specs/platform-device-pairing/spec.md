## Purpose

Allow a user-approved export-agent installation to authenticate to one configured Ratatoskr Platform origin without persisting credentials outside macOS Keychain or masking loss of authorization.

## ADDED Requirements

### Requirement: Explicit Platform pairing

The agent SHALL pair only by presenting a user-supplied, unexpired Platform pairing code to the existing device-pair endpoint with kind `export_agent`. It MUST bind a successful result to the configured HTTPS origin and a non-secret device identifier, and it MUST NOT use provider credentials, browser sessions, cookies, or a local device name as approval evidence.

#### Scenario: Primary-session-approved code is exchanged

- **WHEN** the user supplies a pairing code created by their authenticated primary Platform session for an export agent
- **THEN** the agent exchanges it once with the configured origin and reports a paired state containing the returned non-secret device identity and credential expiry

#### Scenario: Pairing code is refused

- **WHEN** Platform refuses the supplied pairing code
- **THEN** the agent reports pairing failed without persisting a partial identity or any credential material and leaves authenticated archive work unavailable

### Requirement: Credentials are confined to Keychain

The agent SHALL store its device root secret, access credential, and refresh token only in macOS Keychain under an origin- and device-bound record readable solely by the agent process. It MUST retain only non-secret pairing metadata in configuration or the local journal, and MUST NOT expose credential values through logs, errors, diagnostics, URLs, or user-visible status.

#### Scenario: Credential persistence round trip

- **WHEN** pairing succeeds and the agent is restarted
- **THEN** it restores the credential set from the origin-bound Keychain record and restores only non-secret identity/status metadata from local state

#### Scenario: Credential-store failure

- **WHEN** the Keychain record cannot be stored or read
- **THEN** the agent reports a safe credential-storage failure, does not persist credential material elsewhere, and does not start authenticated work

### Requirement: Safe session rotation and recovery

The agent SHALL serialize credential refreshes. A successful refresh MUST replace the access credential and refresh token together before either can be used; an ordinary refresh refusal MUST trigger at most one replacement-session attempt using the stored device root secret, and a successful replacement MUST atomically replace the session credential pair.

#### Scenario: Refresh rotates the credential pair

- **WHEN** an authenticated operation needs a refreshed session and Platform returns replacement credentials
- **THEN** later requests use only the replacement access credential and refresh token and the previously presented refresh token is never sent again

#### Scenario: Refresh refusal recovers from device root secret

- **WHEN** Platform refuses the current refresh token while the device root secret remains valid
- **THEN** the agent opens one replacement device session, persists its returned session credentials, and resumes the pending authenticated operation without pairing again

### Requirement: Revocation produces clean re-pairing-required degradation

The agent SHALL treat an unauthenticated response from both refresh and device-session recovery as revocation or lost authorization. It MUST remove unusable session credentials, prevent further authenticated transport work, preserve source archives and non-secret diagnostic identity, and present an explicit re-pairing-required state. It MUST NOT retry authentication continuously or claim that an upload completed.

#### Scenario: Revoked device cannot recover

- **WHEN** Platform refuses both refresh and replacement device-session requests for a formerly paired device
- **THEN** the agent clears the unusable session credentials, exposes re-pairing-required state, and leaves local archive and journal data intact

#### Scenario: Revoked state does not leak secrets

- **WHEN** the agent records or displays the re-pairing-required state
- **THEN** its logs, errors, diagnostics, and visible status contain no access credential, refresh token, device root secret, or pairing code
