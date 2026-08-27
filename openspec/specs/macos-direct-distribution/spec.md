# macos-direct-distribution Specification

## Purpose

Defines the verifiable macOS application boundary that contains local archive access, network access, release signing, and Apple notarization without broadening user or machine authority.

## Requirements

### Requirement: Distribution bundle has a stable identity
The distributable application SHALL be a macOS `.app` bundle named `Ratatoskr Export Agent.app` with bundle identifier `com.po4yka.ratatoskr.export-agent`, accessory-app presentation, a declared macOS 14 minimum, and non-placeholder short and build versions supplied by the release invocation.

#### Scenario: Release bundle is assembled
- **WHEN** distribution packaging is invoked with valid short and build versions
- **THEN** the resulting bundle metadata contains the stable product identity, versions, accessory presentation, and macOS 14 minimum, and its executable follows the expected bundle layout

#### Scenario: Release version is missing
- **WHEN** distribution packaging is invoked without a valid short version or build version
- **THEN** packaging fails before producing a distributable application

### Requirement: Sandbox authority is minimal and explicit
The distributable application SHALL enable App Sandbox and SHALL grant only outbound network client access and read/write access to files or folders the user selects. It MUST NOT grant inbound network, broad Downloads, home-directory, temporary exception, executable-write, automation, microphone, camera, location, contacts, application-group, Keychain access-group, debug, or hardened-runtime exception entitlements.

#### Scenario: Entitlement policy is verified
- **WHEN** the committed distribution entitlements are checked
- **THEN** the check accepts exactly App Sandbox, outbound network client, and user-selected read/write access and rejects any additional entitlement

#### Scenario: Broad filesystem entitlement is introduced
- **WHEN** a Downloads, home-directory, or temporary-exception entitlement is added to the distribution policy
- **THEN** distribution validation fails and identifies the unexpected entitlement

### Requirement: Persisted folder access remains user-scoped
The sandboxed application SHALL persist access only for folders explicitly selected through the system picker, resolve stored security-scoped bookmarks on later launches, hold scoped access only while needed, and surface stale or denied bookmarks for reauthorization.

#### Scenario: Previously selected folder is restored
- **WHEN** the sandboxed application resolves a valid stored bookmark for a user-selected folder
- **THEN** it can acquire scoped access for that folder without gaining access to an unselected sibling folder and releases the scope when work ends

#### Scenario: Stored bookmark is stale
- **WHEN** the sandbox reports a stored folder bookmark as stale or denies access
- **THEN** the folder remains unavailable for processing and the user is prompted to reauthorize it

### Requirement: Release signatures use hardened Developer ID
Every release application SHALL be signed with an owner-held Developer ID Application identity, a secure timestamp, hardened runtime, and the committed distribution entitlements. An ad hoc, Apple Development, Mac App Distribution, unsigned, or `get-task-allow` signature MUST NOT qualify as release evidence.

#### Scenario: Hardened Developer ID signature is valid
- **WHEN** a release application is signed with the owner Developer ID Application identity
- **THEN** signature validation reports a secure timestamp, hardened runtime, the stable bundle identity, and the exact committed entitlements

#### Scenario: Non-release signature is inspected
- **WHEN** an unsigned, ad hoc, development-signed, or debug-entitled bundle is passed to release validation
- **THEN** validation fails without labeling the bundle signed or release-ready

### Requirement: Notarization evidence is fail-closed
The distribution pipeline SHALL submit the signed archive with `notarytool`, require an accepted response, staple the ticket to the application, validate the stapled ticket, repackage the stapled application, and require Gatekeeper assessment before exposing the CI artifact as notarized.

#### Scenario: Apple accepts a release
- **WHEN** CI has valid owner signing and notarization credentials and Apple accepts the submission
- **THEN** CI exposes an archive containing the stapled application only after signature, stapler, and Gatekeeper checks all pass

#### Scenario: Apple rejects or cannot validate a release
- **WHEN** submission is rejected, stapling fails, or a post-notarization validation fails
- **THEN** the pipeline fails and exposes no artifact labeled notarized

### Requirement: Missing owner credentials are exact blockers
The distribution workflow SHALL consume owner credentials only from CI secrets and SHALL fail before signing with a complete list of missing secret names. Repository files, logs, build artifacts, command-line options, and diagnostics MUST NOT contain private certificate bytes, certificate passwords, or notarization private-key bytes.

#### Scenario: Required CI secrets are absent
- **WHEN** the distribution workflow starts without one or more required owner secrets
- **THEN** it stops before signing and reports each missing secret name without printing any supplied secret value or fabricating signing evidence

#### Scenario: CI credentials are available
- **WHEN** all required owner secrets are available
- **THEN** they are materialized only in runner-temporary files and an ephemeral Keychain that are removed at workflow completion
