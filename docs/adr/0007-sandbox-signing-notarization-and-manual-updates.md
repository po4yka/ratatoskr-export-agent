---
status: accepted
date: 2026-08-27
---

# Sandbox, signing, notarization, and manual updates

Ratatoskr Export Agent will be distributed directly as a sandboxed, hardened, Developer ID-signed and Apple-notarized `.app` inside a ZIP. Updates remain an explicit manual download from the fixed Ratatoskr Export Agent GitHub Releases page; Sparkle is not included because the project does not yet own a signed appcast, updater signing key, automatic-install recovery path, or release availability contract.

## Context

The SwiftPM executable needs outbound Platform access and persistent read/write access to folders the user selects. It does not need incoming network access, broad Downloads or home-directory access, Apple Events, executable writes, privileged helpers, Keychain sharing, or hardened-runtime exceptions. The app already persists security-scoped bookmarks and keeps device credentials in its default non-synchronizing Keychain item.

Direct distribution makes App Sandbox optional but makes Developer ID, hardened runtime, secure timestamp, and notarization the release trust boundary. Owner-held signing and App Store Connect credentials must never enter the repository.

## Considered options

1. **Manual download, direct notarized distribution:** no runtime dependency or background update traffic; users compare and install releases themselves.
2. **Sparkle:** a better update experience, but adds privileged update code, automatic network behavior, an appcast availability contract, a second signing key, and rollback/recovery obligations that do not exist today.
3. **No update entry point:** simplest implementation, but leaves installed version visibility and release discovery implicit.
4. **Mac App Store:** strong platform distribution, but changes sandbox, review, entitlement, and release ownership and is not part of the self-hosted delivery model.
5. **Unsandboxed Developer ID app:** permitted by Apple, but broad default filesystem authority contradicts Ratatoskr's explicit-folder boundary.

## Decision

The bundle remains SwiftPM-first with identifier `com.po4yka.ratatoskr.export-agent`. Its entitlement allowlist is exactly:

- `com.apple.security.app-sandbox`;
- `com.apple.security.files.user-selected.read-write`;
- `com.apple.security.network.client`.

Release CI imports one owner Developer ID Application identity into an ephemeral Keychain, signs with hardened runtime and a secure timestamp, submits through `notarytool`, staples the accepted ticket, and requires signature, entitlement, stapler, and Gatekeeper validation before uploading the final ZIP. Missing or rejected owner credentials stop the workflow; unsigned and ad hoc bundles remain development evidence only.

The menu action `Check for Updates…` asks macOS to open only `https://github.com/po4yka/ratatoskr-export-agent/releases/latest`. The agent does not fetch a feed, compare remote versions, download executable code, install updates, or schedule update checks.

## Consequences

- The app's filesystem reach is enforced by App Sandbox and user-selected security-scoped bookmarks rather than convention alone.
- Users must download and replace the app manually and can remain on an old version.
- No Sparkle dependency, appcast service, update signing key, or update background process is introduced.
- Release automation depends on owner Apple credentials and GitHub Actions; local green gates cannot prove notarization.
- Changing to Sparkle, the Mac App Store, a privileged helper, or a different release host requires a new ADR and threat-model update.

## Security and privacy

The app never receives provider credentials or browser sessions. Update discovery exposes no archive, folder, endpoint, credential, or device data to GitHub; the browser opens only after explicit user action. Signing secrets are accepted only as CI environment values, decoded under the runner temporary directory, used from an ephemeral Keychain, and removed on exit. The certificate password is referenced by environment-variable name when OpenSSL reads it and is not embedded as a command-line value.

## macOS lifecycle and distribution

Normal development builds do not require notarization. The ad hoc sandbox smoke verifies startup containment but deliberately fails release validation. A releasable ZIP requires an owner-authorized hosted run plus separate clean-machine acceptance for Gatekeeper launch, folder selection/bookmark restoration, Keychain pairing, and upload behavior. There is no LaunchAgent, login item, or privileged helper in this decision.

## Schema impact

No database, Platform API, provider archive, upload, journal, or cross-repository contract changes. The local support-report encoding changes its update diagnostic from a deferred scalar to a manual-download state with an optional current bundle version; development status permits updating this current local shape in place.

## Validation

Normal CI assembles the bundle, validates metadata and the entitlement allowlist, rejects unsigned/ad hoc release claims, and runs an ad hoc sandbox smoke. Distribution CI additionally requires Developer ID authority, hardened runtime, secure timestamp, exact signed entitlements, accepted notarization, a stapled ticket, Gatekeeper acceptance, and a final SHA-256 digest.

## Follow-up

The owner must configure the five secrets listed in `docs/DISTRIBUTION.md` and retain the first successful workflow URL, commit SHA, notary submission ID, artifact digest, and validation output. The workspace must later pin that exact commit with compatible Platform and archive-service commits and run the synthetic end-to-end flow; repository push and hosted notarization do not prove workspace integration.
