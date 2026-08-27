## Why

Ratatoskr Export Agent has runnable local behavior but no distributable `.app`, sandbox policy, hardened signature, notarization path, or selected update experience. Plan item 10 closes that delivery boundary while reporting owner-credential blockers exactly instead of treating an unsigned or ad hoc build as release evidence.

## What Changes

- Package the SwiftPM executable as a direct-distribution macOS application with App Sandbox enabled, hardened runtime signing, and only the user-selected read/write and outbound-network entitlements its current behavior requires.
- Add deterministic checks for bundle shape, declared entitlements, hardened signing, stapled notarization, Gatekeeper acceptance, and privacy-sensitive capability drift.
- Add a GitHub Actions distribution workflow that imports owner-held credentials into an ephemeral keychain, signs with Developer ID Application, submits with `notarytool`, staples the accepted ticket, re-verifies the artifact, and publishes no release when credentials or validation are absent.
- Select manual download from the repository's GitHub Releases page instead of Sparkle, record that decision in ADR-0007, and replace the inert update diagnostic with a local current-version/manual-download presentation and explicit user action. The agent performs no automatic update request.
- Document exact owner-secret blockers, release/recovery commands, security-scoped bookmark justification, permissions and privacy impact, and the still-pending workspace pin/integration harness.
- Add no provider login automation, privileged helper, broad Downloads or home-directory access, update feed, updater signing key, or production dependency.

## Capabilities

### New Capabilities

- `macos-direct-distribution`: Defines the sandboxed application bundle, hardened Developer ID signature, notarization, stapling, Gatekeeper validation, and fail-closed release evidence.
- `manual-application-update`: Defines the explicit manual-download update action, current-version presentation, fixed trusted destination, and absence of automatic update traffic.

### Modified Capabilities

- `local-operational-diagnostics`: Replaces the bootstrap-only deferred update state with truthful manual-update availability and current-version diagnostics without an update network check.

## Impact

- Affects distribution packaging/scripts, entitlements and bundle metadata, the menu and diagnostics presentation/model, CI workflows, release and workspace-integration documentation, and ADR-0007.
- Adds no Swift package dependency and changes no Platform, provider, upload, archive, journal, or Keychain contract.
- Requires owner-provided Developer ID Application material and App Store Connect notarization API credentials for notarized CI evidence; until those secrets exist, the committed unsigned packaging and structural validation remain useful but notarization stays explicitly blocked.
