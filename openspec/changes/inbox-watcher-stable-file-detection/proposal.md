## Why

Exports arrive as growing downloads: browsers write archives through temporary names (.download, .crdownload, .part) for minutes at a time. Hashing or uploading a half-written archive corrupts the backup pipeline downstream, so the agent needs a watcher that observes configured inbox folders and a detector that queues a file only once the download has demonstrably finished.

## What Changes

- Add folder observation over the enabled watched folders: filesystem events are hints that become debounced directory scans; each scan reconciles candidates. A scan also runs once at start so files already present in a folder are discovered.
- Add completed-download stability detection: a candidate is queued only after its size and modification time stay unchanged across a quiet interval AND a writer-hold probe passes where the platform can detect one.
- Add partial-file heuristics: files carrying known temporary download suffixes are never queued regardless of how stable they look.
- Add safety gates on candidates: only regular files are eligible; unreadable files and files above the configured size ceiling are rejected with a recorded reason rather than queued.
- Add watcher lifecycle with degradation: start/stop over multiple folders, per-folder degraded state when a folder disappears or cannot be read while watching, and continued healthy watching of the remaining folders.
- Emit stable candidates as `StableArchiveCandidate` values for later pipeline stages (hashing, journal, upload land in their own changes).

## Capabilities

### New Capabilities

- `inbox-folder-watching`: lifecycle of folder observation — starting and stopping over enabled folders, debounce of event bursts into scans, discovery including files present before start, idempotent repeated events, and per-folder degradation when a folder becomes unavailable while others keep working.
- `stable-download-detection`: the decision that an observed file is a finished download — quiet-period evidence from size and modification time, the writer-hold probe where detectable, temporary-suffix exclusion, regular-file-only eligibility, readability, and the configured size ceiling.

### Modified Capabilities

<!-- none: this change introduces new behaviour without altering existing requirements -->

## Impact

- New types in the `AgentCore` target: stability evaluation (pure logic), metadata probing abstraction, debounce scheduling abstraction, the FSEvents-backed folder monitor, and the coordinating actor that ties folders, events, and detection together. No existing type changes its public interface.
- `WatchedFolderRegistry` remains the source of folder identity and access resolution; the coordinator consumes resolved folder URLs, it does not duplicate registry state.
- Tests grow in `AgentCoreTests` using fixture write sequences against real temp directories plus injected clocks/schedulers, keeping every scenario deterministic.
- No UI, persistence, network, or Keychain surface changes. Nothing here logs paths or filenames.
