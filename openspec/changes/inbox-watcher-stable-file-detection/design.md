## Context

The package already owns typed configuration (`AgentConfiguration.maxArchiveBytes` gives the ceiling), watched-folder preferences with security-scoped bookmarks, and `WatchedFolderRegistry.accessState(for:)` which resolves a folder to `.accessible(URL)` or an actionable failure. There is no observation of those folders yet and no candidate concept. The tree is strict-concurrency Swift 6 with tight SwiftLint ceilings (file 183 lines, type body 128, function body 35), so the feature decomposes into small pure cores plus thin system wrappers.

## Goals / Non-Goals

**Goals:**

- Deterministic, fully testable detection logic; every spec scenario runs against fixture sequences with injected time.
- A real folder-observation mechanism that works under security-scoped access and survives event loss without wrong queueing (worst case is late discovery, never premature).
- Degradation isolated per folder.

**Non-Goals:**

- Persisted journal, hashing, upload, notifications (later plan items). The coordinator emits in-memory `StableArchiveCandidate` values and keeps nothing durable.
- Periodic background reconciliation scans (arrives with the journal item); this change reconciles at start and on debounced events only.
- Provider hinting/classification of archive contents.
- Any UI wiring beyond what later items add.

## Decisions

### FSEvents over DispatchSource vnode monitoring

DispatchSource vnode sources watch one open file descriptor each: they cannot discover newly created files (there is no fd until after arrival) and die on rename/delete — exactly the churn an inbox lives in. FSEvents watches directories natively, reports created/renamed/modified paths with file-level detail enabled, coalesces bursts itself, and needs only read access to the resolved folder path, which security-scoped access already grants while the scope is held. The monitor is a thin wrapper around `FSEventStreamCreate` scheduled on its own serial queue; every decision (debounce, stability, degradation) sits above it behind small protocols so tests never depend on kernel event timing.

Alternative considered: polling directory listings on a timer. Rejected as the primary mechanism (latency and idle cost) though it survives as the shape of the reconciliation scan performed at start and after each debounced burst.

### Notifications are hints; scans are authoritative

Per docs/ARCHITECTURE.md, events only schedule a debounced scan; the scan lists the directory and diffs it against known candidates. Consequences: missed or coalesced events cost at most latency; duplicate events are naturally idempotent because state is keyed by path; a rename from temporary to final name is discovered as a fresh path even if the rename event itself was swallowed.

### Pure stability core with injected clock

`DownloadStabilityEvaluator` decides from three inputs — previous snapshot, current snapshot, elapsed quiet time — plus the writer-probe flag. `QuietPeriodTracker` keys per-path first-seen/last-change state around it. Both take `now: Date` as a parameter; no production type reads the wall clock during tests. This makes the whole matrix (grow, touch, hold-still, suffix, oversized, unreadable, non-regular, writer-held) executable as fixture write sequences with a virtual clock.

### Writer-hold probe is advisory by platform design

Darwin exposes no portable way to ask whether another process holds a file open; POSIX record locks do not cover browser writers. The probe therefore attempts to open the file for writing without creating/truncating and treats EACCES/EBUSY as "writer detected", documenting honestly that a passing probe is not proof of no-writer. Quiet-period evidence carries the guarantee; the probe adds coverage where detectable, matching the spec's wording.

### Debounce and reassessment through one scheduler seam

A `WatchScheduling` protocol (schedule at deadline / cancel) abstracts the dispatch timer. Production uses a serial dispatch queue; tests use a manual scheduler advancing virtual time. Debounced scans and per-candidate stability re-assessments are both scheduled through it, so debounce behaviour and quiet-interval checks are tested deterministically without sleeps.

### Coordinator is an actor fed by the monitor's queue

FSEvents callbacks arrive off the main thread; the coordinating actor serialises scan/diff/stability state. Folder URLs come in as resolved `[WatchedFolderTarget]` produced by the caller from `WatchedFolderRegistry` (which stays `@MainActor` and untouched). During each scan the actor verifies the folder still exists; failure marks just that folder degraded and drops its monitor.

## Risks / Trade-offs

- [Real FSEvents delivery timing varies] → Only one integration test touches the live stream, asserting delivery within a generous window; all other scenarios run on scripted monitors. Late delivery degrades latency, not correctness, because scans re-list the directory.
- [Event stream silently dies (folder replaced, stream stopped)] → Every scan checks folder existence and the coordinator offers stop/restart lifecycle; degradation is surfaced as folder status rather than silent silence.
- [Rename preserving old mtime looks instantly stable] → Stability is measured from the tracker's own first observation, so a renamed-in file still waits one full quiet interval before queueing.
- [Probe open-for-write could perturb a writer] → The probe opens with O_EVTONLY-style semantics (no truncate/create, immediate close); browsers writing sequentially are unaffected by a failed/successful open attempt.
- [SwiftLint ceilings force many small files] → Accepted deliberately: evaluator, tracker, heuristics, monitor, coordinator each stay far below the limits and stay independently testable.

## Migration Plan

Additive only: new files, new tests, no existing public interface changes. Feature is unreleased; rollback is reverting the change.

## Open Questions

None blocking. The quiet interval default (30 s) and debounce default (0.5 s) are constants in the coordinator's configuration struct and can be tuned later without contract changes.
