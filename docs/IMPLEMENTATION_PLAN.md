# Export Agent implementation plan

1. Create macOS app project, typed configuration, unified logging, test targets, and distribution profiles.
2. Implement directory picker/security-scoped bookmark and preferences.
3. Implement watcher plus completed/stable-file detector.
4. Implement streaming hash, shallow classification, immutable local archive, and atomic operations.
5. Implement durable local journal and crash recovery.
6. Add Platform device pairing with Keychain credential storage.
7. Implement idempotent/resumable upload and offline retry queue.
8. Track backend operation/completeness and present safe UI/notifications.
9. Add reminders, permission/disk diagnostics, exportable redacted support report.
10. Finalize sandbox/entitlements, signing, notarization, update model, and workspace integration.

Definition of Done: synthetic exports survive crashes/offline/duplicates, local original remains intact, upload is verified/idempotent, secrets/content stay private, packaging and workspace flow pass. Deferred: provider login and automatic download links.
