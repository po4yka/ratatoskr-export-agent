## Context

See `proposal.md` for motivation. The checkout is SwiftPM-first and produces a bare executable, not an Xcode archive or `.app`. Folder access already funnels through `SecurityScopedBookmarkStore`; network traffic is outbound to a configured HTTPS Platform origin; credentials use the default application Keychain boundary; notifications and user-selected support-report export need no additional sandbox grant. Update diagnostics deliberately remain inert pending this change.

Apple requires direct-distribution software to use a Developer ID Application signature, secure timestamp, and hardened runtime before notarization. `notarytool` accepts a ZIP containing an application; the ticket must be stapled to the application before producing the final ZIP. App Sandbox is optional for direct distribution but retained here because narrow, user-selected folder authority is a product boundary rather than an App Store requirement.

The owner-held certificate and notarization API key are not repository material. Planning therefore separates locally testable bundle/policy structure from Apple-backed release evidence and never treats the former as the latter.

## Goals / Non-Goals

**Goals:**

- Produce one deterministic `.app` layout from the existing SwiftPM release executable.
- Keep sandbox entitlements reviewable as a small exact allowlist.
- Make signing, notarization, stapling, and Gatekeeper checks reproducible in owner-authorized CI.
- Replace the deferred update state with a real manual-download user flow and no automatic update traffic.
- State the repository/workspace compatibility and evidence boundary while the workspace has no pinning harness.

**Non-Goals:**

- Mac App Store packaging, installer packages, DMGs, privileged helpers, login items, Sparkle, an update feed, automatic download/install, or publishing a GitHub Release.
- A new Keychain access group or provisioning profile; the application has no advanced capability that requires either.
- Changing Platform, receiver, provider-parser, archive, upload, journal, or completeness contracts.
- Calling an unsigned local build signed, notarized, Gatekeeper-accepted, or production-ready.

## Decisions

### Direct distribution stays SwiftPM-first

Add `Distribution/Info.plist.template` and `Distribution/RatatoskrExportAgent.entitlements`, plus narrow scripts that build and assemble the bundle, validate policy, sign, submit, staple, and repackage. The bundle identifier is `com.po4yka.ratatoskr.export-agent`, matching the existing Keychain service namespace. The packaging command requires an explicit short version and build version rather than guessing from a dirty checkout.

An Xcode project was considered because Organizer provides signing and notarization flows. It is rejected for this milestone: the package has no Apple-framework dependency that needs project configuration, the current CI and local gates are SwiftPM-native, and a generated project would add a second mutable build graph. A hand-written application bundle is acceptable because it contains one executable and no nested code.

### Entitlements are an exact allowlist

The distribution entitlement file contains only:

- `com.apple.security.app-sandbox` for containment;
- `com.apple.security.files.user-selected.read-write` for picker-selected inbox/archive/support-report locations and persistent security-scoped bookmarks;
- `com.apple.security.network.client` for authenticated outbound Platform upload and operation tracking.

The verifier compares normalized entitlement keys and Boolean values against that allowlist. It rejects `get-task-allow`, Downloads/home grants, temporary exceptions, Apple Events, inbound network, executable writes, application groups, Keychain access groups, and hardened-runtime exceptions. No entitlement is added for notifications, Keychain's default application access, or opening an HTTPS page in the default browser.

Running without App Sandbox was considered because Apple permits it for notarized direct distribution. It is rejected: broad default filesystem reach contradicts the agent's explicit-folder security boundary and would make bookmark enforcement accidental rather than structural.

### CI separates structural packaging from owner-authorized notarization

The normal `ci.yml` adds unsigned bundle assembly and exact policy validation to the documented gate. A separate manual `distribution.yml` imports one Developer ID Application PKCS#12 into an ephemeral Keychain, signs with `--options runtime --timestamp`, validates the signature and entitlements, submits a ZIP with `notarytool --wait`, staples and validates the application ticket, runs Gatekeeper assessment, builds a new ZIP from the stapled app, and uploads that ZIP as the CI artifact.

The workflow validates these secrets before materializing any credential:

- `APPLE_DEVELOPER_ID_APPLICATION_P12_BASE64`
- `APPLE_DEVELOPER_ID_APPLICATION_P12_PASSWORD`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_PRIVATE_KEY_BASE64`

The workflow derives the one imported `Developer ID Application:` identity rather than accepting an untrusted free-form signing identity. Certificate/key files and the ephemeral Keychain live under the runner's temporary directory, receive restrictive permissions, and are removed by a trap. Missing secrets produce names only. Notary rejection fetches the submission log as an ephemeral CI diagnostic; artifact publication remains downstream of every validation.

Using Apple ID plus an app-specific password was considered. App Store Connect API-key authentication is selected because it is scoped and revocable without storing an interactive account password. A Developer ID Installer certificate is unnecessary because the deliverable is a ZIP containing an app, not a flat installer package.

### Manual download is the update mechanism

ADR-0007 records manual download from the fixed `https://github.com/po4yka/ratatoskr-export-agent/releases/latest` page. A small injected URL opener backs `Check for Updates…`; the production adapter asks `NSWorkspace` to open only that compiled-in URL, and failure becomes a generic alert. Current version comes from `CFBundleShortVersionString`; tests inject version metadata and the opener. Diagnostics change from `deferredPendingDistributionDecision` to a manual-download state with an optional current version.

Sparkle was considered and rejected for now. It would add runtime code with elevated update responsibility, an appcast hosting and availability contract, a second update-signing key, automatic network behavior, and additional release validation. Manual download is less convenient but matches the current self-hosted, owner-operated release maturity and adds no dependency. A future change may adopt Sparkle only with a new ADR and an end-to-end signed feed/recovery design.

### Workspace integration is documentation until the harness exists

Add a repository-owned integration note that names compatible upstream responsibilities, synthetic end-to-end flow, rollout order, rollback, old-agent behavior, privacy constraints, and exact evidence categories. It must say that the workspace currently has no `workspace.toml`, lock, submodule pin, or runnable `ws` integration profile; a repository push is not workspace integration proof. No shared contract changes are introduced, so this change remains local rather than inventing a workspace-store capability.

## Risks / Trade-offs

- [Manual updates can leave users on an old version] → Show current version and a persistent explicit update action; defer automation until a signed feed has an owner and recovery story.
- [A custom bundle script can drift from macOS requirements] → Keep one executable, validate metadata and exact entitlements in normal CI, and validate signature, ticket, and Gatekeeper in distribution CI.
- [Sandboxing reveals existing implicit filesystem assumptions] → Exercise bookmark restoration with the packaged app where CI permits, keep all folder access behind the existing bookmark abstraction, and fail closed on stale or denied access.
- [CI secrets may be absent or malformed] → Validate names before work, let Apple and `codesign` validate content, publish no notarized artifact on any failure, and document the exact owner actions.
- [GitHub Releases is unavailable or the repository moves] → Treat browser-open failure as actionable and change the compiled-in destination only through a reviewed release change; do not add fallback hosts or redirects inside the agent.
- [Notary acceptance alone can hide warnings or local launch defects] → Capture the notary log, require stapler/Gatekeeper validation, retain the smoke launch in the product gate, and document that clean-machine installation remains separate release evidence.

## Migration Plan

1. Land bundle metadata, entitlements, structural verification, manual update behavior, ADR, and release/workspace documentation with local and normal CI green.
2. Configure the five owner secrets in the repository Actions environment with the least repository scope.
3. Run `distribution.yml` manually for an explicit short/build version; retain the workflow run URL, commit SHA, artifact digest, notary submission ID, and post-staple validation output as release evidence.
4. Install the resulting ZIP on a clean compatible Mac, confirm Gatekeeper launch, folder selection/restoration, Keychain pairing, upload, and manual update action. This is device acceptance, not implied by CI.
5. When the workspace pinning harness exists, pin the exact export-agent commit with compatible Platform/contracts/services commits and run the documented synthetic flow.

Rollback removes the update menu action and returns diagnostics to the deferred state, but it does not revoke already distributed binaries. If signing material is compromised, the owner revokes the certificate/key in Apple systems, removes the affected CI secrets, records impacted notary submission IDs, and issues a freshly signed replacement; the repository cannot automate certificate revocation.
