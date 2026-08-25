# Proposal: folder-preferences-security-bookmarks

## Why

docs/IMPLEMENTATION_PLAN.md plan item 2 asks for the directory picker, security-scoped bookmarks, and preferences. A sandboxed macOS agent cannot hold arbitrary filesystem access across launches: access to a user-chosen folder survives restarts only as a security-scoped bookmark created at pick time. The scaffolded configuration document currently carries `watchedFolders` as bare path strings that grant no access and would go stale silently, and there is no UI to choose or manage folders. Until this lands, the watcher planned next has no trustworthy source of watchable folders.

## What Changes

- Add a persisted watched-folder preferences document, schema version 1 only, decoded strictly like the existing typed configuration: per-folder entry with a stable generated ID, sanitized display path metadata, enabled flag, archive-after-upload policy, and security-scoped bookmark data. Missing file yields an empty registry; invalid documents are rejected naming the reason; saves are atomic.
- Add a security-scoped bookmark lifecycle service behind a narrow protocol: create a bookmark when the user picks a folder, resolve it back to an accessible URL (starting scoped access) on demand and after restarts, relinquish (stop accessing, drop stored data) on removal.
- Map resolution failures onto typed, actionable folder-access states - needs reauthorization, missing, permission denied, unreadable - so a broken bookmark becomes a visible state on the affected folder row instead of silent watch death.
- Add a Settings window reachable from the status-bar item menu ("Settings…", plus "Quit Ratatoskr"): lists watched folders with add/remove, per-folder enable toggle and archive-policy selection, and shows each folder's current access state with a re-authorize action where applicable. Folder picking runs through NSOpenPanel; picking creates the bookmark and persists the preference before the window reports success.
- **BREAKING** (permitted by development status): remove the `watchedFolders` field from the configuration document. Folder ownership moves entirely to the preferences store so exactly one persisted source of truth exists; the configuration file keeps backend endpoint and budgets.

Out of scope and unchanged: actual inbox observation/stability detection (plan item 3), fingerprinting, uploads, device authentication, reminders, notifications, Keychain.

## Capabilities

### New Capabilities

- `watched-folder-preferences`: the persisted per-folder registry - document shape, strict loading/saving and validation, and the settings surface where folders are added, removed, enabled, and given an archive policy.
- `security-scoped-folder-access`: the bookmark lifecycle - creating scoped bookmarks at pick time, resolving them to accessible URLs across restarts, relinquishing them on removal, and classifying resolution failures into actionable states.

### Modified Capabilities

- `typed-configuration`: the `watchedFolders` field is removed from the schema-version-1 document and its empty-entry rejection rule disappears with it (**BREAKING**, allowed while development status holds).

## Impact

- `Sources/AgentCore/`: new preference document types plus strict decoding and atomic save; new bookmark-store abstraction with a FileManager-backed implementation (Foundation-only, unit-testable); removal of `watchedFolders` from the configuration document, its decoder, its rejection enum, and the corresponding tests.
- `Sources/RatatoskrExportAgent/`: status-bar menu construction, Settings window controller hosting the SwiftUI folder-settings view, NSOpenPanel picker adapter, and a view model that carries add/remove/toggle/policy/access-state logic test-first.
- Tests: `AgentCoreTests` for document round-trip and validation, bookmark create/resolve round-trip where CI can exercise it headlessly, and failure-state mapping; `RatatoskrExportAgentTests` for menu composition and view-model folder flows against injected stubs.
- No behaviour visible to other repositories changes; nothing is cited from or added to the ratatoskr-workspace store. Privacy rules hold: paths stay out of logs, bookmark bytes live only in the local preferences document, and no archive content is touched.
- README status block is updated to reflect delivered preferences and bookmark handling after implementation.
