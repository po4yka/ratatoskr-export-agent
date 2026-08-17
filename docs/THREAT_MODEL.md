# Export Agent threat model

## Assets

Personal export ZIPs, local filesystem access, immutable archive, device credentials, upload integrity, backend address, notifications, and update channel.

## Threats and controls

- **Overbroad file access:** explicit directory picker/security-scoped bookmarks; no home-directory crawl.
- **Partial/tampered file:** stability checks, hash before/after move/upload, shallow ZIP validation.
- **Path/symlink race:** file coordination, canonical scoped roots, no source-derived destination paths.
- **Archive loss:** preserve original before upload; atomic operations; disk-space checks; journal recovery.
- **Credential theft:** Keychain access controls, rotation/revoke, no logs/backups of secret material.
- **MITM/wrong server:** TLS, explicit configured endpoint, pairing confirmation, signed updates.
- **Content/log leak:** no archive parsing/text/filenames in telemetry or notifications.
- **Malicious update/helper:** code signing, notarization, pinned release provenance, minimal entitlements.

Re-review for automatic email-link download, privileged helper, remote administration, cloud-synced archive directories, or auto-delete.
