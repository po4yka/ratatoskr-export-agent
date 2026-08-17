# Security Policy for Ratatoskr Export Agent

Report vulnerabilities privately. Do not publish local archive paths, ZIP contents, device credentials, Keychain dumps, user notifications, production endpoints, or logs containing filenames/content.

Security review is required for directory permissions/bookmarks, watcher/helper architecture, file moves, archive classification, Keychain, pairing, TLS, uploads, update distribution, entitlements, signing/notarization, and diagnostics export.

Baseline: user-scoped folders only; no broad disk scan; stable-file detection; content-addressed immutable archive; no archive parsing beyond safe shallow classification; Keychain credentials; TLS and endpoint validation; idempotent/resumable upload; redacted unified logging; no provider login/session automation.
