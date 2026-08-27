# Export Agent threat model

## Assets

Personal export ZIPs, local filesystem access, immutable archive, device credentials, upload integrity, backend address, notifications, and update channel.

## Threats and controls

- **Overbroad file access:** explicit directory picker/security-scoped bookmarks; no home-directory crawl.
- **Partial/tampered file:** stability checks, hash before/after move/upload, shallow ZIP validation.
- **Path/symlink race:** file coordination, canonical scoped roots, no source-derived destination paths.
- **Archive loss:** preserve original before upload; atomic operations; disk-space checks; journal recovery.
- **Credential theft:** Keychain access controls, rotation/revoke, no logs/backups of runtime or signing secret material; CI signing assets exist only in runner-temporary files and an ephemeral Keychain.
- **MITM/wrong server:** TLS, explicit configured endpoint, pairing confirmation, signed updates.
- **Content/log leak:** no archive parsing/text/filenames in telemetry or notifications.
- **Malicious update/helper:** exact minimal entitlements, hardened Developer ID signing, notarization, stapling, Gatekeeper validation, pinned workflow actions, and no helper or automatic installer.
- **Update redirection or silent download:** one compiled-in HTTPS GitHub Releases destination opened only by explicit user action; no feed, polling, executable download, or install path in the agent.
- **False release evidence:** unsigned and ad hoc bundles fail release validation; missing owner secrets, notary rejection, stapling failure, or Gatekeeper rejection prevent hosted artifact upload.

Re-review for Sparkle or another updater, automatic email-link download, privileged helper, remote administration, cloud-synced archive directories, or auto-delete.
