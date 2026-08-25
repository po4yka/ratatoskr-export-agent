# Design: folder-preferences-security-bookmarks

## Context

See proposal.md - Why. The package has three targets: `AgentCore` (typed configuration, Foundation-only, fully unit-tested), `AgentLog`, and the thin AppKit executable that installs one status-bar item with no menu and supports headless `--smoke`. The configuration document currently carries `watchedFolders` as bare strings. SwiftLint enforces hard size ceilings (file 183 lines, function body 35, type body 128), so new types stay small by construction.

## Goals / Non-Goals

**Goals:**

- One persisted source of truth for which folders are watched, carrying everything the future watcher needs: identity, enablement, archive policy, and restart-proof scoped access.
- Bookmark lifecycle logic testable headlessly in CI (`swift test`) without GUI interaction or sandbox entitlements.
- Resolution failures surface as typed, displayable states instead of exceptions escaping or being swallowed.
- The Settings window is thin rendering over a test-first view model; the existing smoke path stays byte-for-byte compatible.

**Non-Goals:**

- Actual inbox watching, stability detection, fingerprinting, uploads (plan items 3-5).
- Sandbox entitlements, signing, LaunchAgent packaging (plan item 9).
- Multi-instance/profile separation, Keychain, reminders.
- Watching many folders concurrently or recursive subfolder selection.

## Decisions

### D1: Folder ownership moves out of the configuration document

The configuration file keeps backend endpoint and budgets only; `watchedFolders` is deleted from schema version 1 and documents containing it are rejected as unknown fields (the existing decoder already names the offender). The new preferences document is a separate persisted artifact because bookmark bytes are opaque, machine-generated blobs that a hand-edited config cannot legitimately contain, and merging them would keep two writers for one concern.

Alternative considered: keeping `watchedFolders` alongside a bookmark registry - rejected as a dual source of truth that would mislead the watcher built next.

### D2: Preferences document mirrors typed-configuration conventions

A `Codable` value type decoded by hand: `schemaVersion` must equal 1 before anything else, the key set is compared against known keys, duplicates IDs and empty bookmark data abort loading naming the entry, and errors carry the file location plus reason without raw contents - the exact shape `AgentConfiguration` already established. Saving encodes once and writes with `.atomic`. Defaults on missing file: empty registry. Archive policy is a two-case string enum, `archiveAfterUpload` (default) and `preserveInPlace`; a Boolean named "policy" was rejected because the settings UI needs a labelled choice and a third policy is plausible later without schema churn.

The small strict-decoding scaffolding (version gate, `AnyCodingKey`) is duplicated between the two documents rather than extracted; at two call sites an abstraction saves less than it costs, and SwiftLint ceilings discourage wide files.

### D3: Bookmark service is a narrow protocol in AgentCore

`AgentCore` gains `FolderBookmarkStoring`: create bookmark data for a picked directory URL, resolve data back to a directory URL (reporting whether the bookmark came back stale), and start/stop scoped access around use. The production implementation wraps `NSURL` bookmark APIs using `.withSecurityScope` on both ends; nothing else in the package touches bookmark APIs, so sandbox hardening later changes exactly one type.

### D4: Access states and their classification

`FolderAccessState` is `accessible`, `needsReauthorization`, `missing`, or `denied`. Classification is a pure function over three observations, each independently unit-testable:

1. bookmark data fails to parse or resolve -> `needsReauthorization`;
2. resolution reports the bookmark as stale while the target still exists (folder was moved or replaced) -> `needsReauthorization`, since only the user can re-grant scope;
3. resolution succeeds but the target no longer exists at the resolved path -> `missing`;
4. an existence/readability probe fails with a permission code -> `denied`.

A deleted folder therefore reads as `missing` (path still resolvable, existence probe negative), matching the spec scenarios. States carry no strings; the UI owns wording, so diagnostics never leak paths through error text.

### D5: CI-testability of the bookmark round trip

`swift test` runs unsandboxed on macOS, where security-scoped bookmark creation and resolution are permitted (scope enforcement begins at access time, and start/stop calls are harmless no-ops without a sandbox). The round-trip tests therefore exercise the real FileManager-backed store against temporary directories. Should a future environment refuse creation, the acceptance criterion allows documented instrumented evidence; the task list records the observed evidence either way. Failure-state classification is pure and needs no such environment.

### D6: AppKit shell grows a menu and one window, not a SwiftUI app lifecycle

Converting to SwiftUI `App`/`MenuBarExtra` would rewrite the startup path that smoke mode pins down. Instead: `applyBootstrapPresentation` additionally attaches an `NSMenu` with "Settings…" and "Quit Ratatoskr" to the existing status item; choosing Settings shows a lazily created `NSWindow` hosting `NSHostingView` with the SwiftUI folder-settings view; the window activates the app when opened so it takes focus despite the accessory policy. Smoke mode runs the identical sequence and never opens the window, so its tests hold unchanged.

All behaviour lives in `FolderSettingsViewModel` (@MainActor, observable): it takes the preferences store and bookmark store as protocols, exposes rows (display path, enabled, policy, access state), and implements add (pick result -> bookmark -> persist -> then report success), remove-with-confirmation, toggle, and policy change. The SwiftUI view and the `NSOpenPanel` adapter have no logic worth testing headlessly; their tasks say so in one line each.

### D7: Duplicate adds collapse at registration time

Adding a folder whose standardized path equals an existing entry's stored path updates nothing and returns the existing entry. Identity here is path-based and advisory - content-hash identity belongs to archives, not folders - and is enough to make double-picking idempotent.

## Risks / Trade-offs

- [Security-scoped bookmark behaviour differs once real sandbox entitlements land] -> all bookmark use funnels through one protocol; item 9 revalidates with entitlements and adjusts only the concrete store.
- [Base64 bookmark bytes grow the document] -> a handful of folders times a few KiB each is negligible; no compression until measured otherwise.
- [Path-based duplicate detection misses renamed folders] -> acceptable: worst case is a second entry the user removes; archive-level deduplication remains hash-based.
- [Accessory apps and window focus misbehave] -> opening Settings activates the app ignoring other sessions and orders the window front; residual quirks are cosmetic, not behavioural.
- [Strict rejection surprises configs written for the scaffold] -> intentional under development status; the unknown-field error names `watchedFolders` so the fix is mechanical.
- [SwiftLint ceilings bite view-model growth] -> rows and actions already decompose naturally; file splits along row-model boundaries if needed.

## Migration Plan

No persisted agent state exists in the wild; there is nothing to migrate. Rollback is reverting the merge commit. Configuration files authored against the scaffold that declare `watchedFolders` will be rejected with a message naming that field - the documented development-status contract.

## Open Questions

None. The remaining unknown (bookmark behaviour under real entitlements) is deferred to plan item 9 by design.
