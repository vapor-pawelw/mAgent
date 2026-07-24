# Thread & Session Lifecycle

## Thread Creation (Pending Thread Pattern)

`ThreadLifecycleService.createThread` (forwarded via `ThreadManager.createThread`) registers the thread in the sidebar immediately (phase 1: name generation only), then runs git worktree + tmux setup in the background (phase 2). The thread is tracked in `ThreadStore.pendingThreadIds: Set<UUID>` while phase 2 runs.

- `SplitViewController.showThread` skips the worktree-existence check for pending threads.
- `ThreadDetailViewController.setupTabs` detects pending via `pendingThreadIds`, shows overlay, waits for `.magentThreadCreationFinished`.
- On error, the pending thread is removed via `delegate?.threadManager(self, didDeleteThread:)` and the notification fires with `"error"` in userInfo.
- Pending threads are never persisted; only save after phase 2 succeeds.
- New tmux sessions must seed `sessionLastVisitedAt` immediately when registered, or idle eviction treats them as ancient after the user switches away.

## Moving an Agent Tab to a New Thread

`Move to New Thread…` is a destructive ownership transfer for an idle Claude or Codex terminal tab with a persisted conversation ID. It is not a context export and must never silently fall back to a fresh conversation.

The operation:

1. Refreshes runtime busy state and refuses tabs that are busy, waiting for input, Magent-busy, or contain unsubmitted input.
2. Snapshots the tab's conversation ID, agent type, display name/manual-rename marker, forwarded marker, pin, Keep Alive, unread markers, and submitted-prompt history.
3. Creates a new branch/worktree from the source thread's actual branch and inherits its section, sidebar placement, and Local Sync snapshot.
4. Creates a uniquely identified recovery stash for staged, unstaged, and non-ignored untracked changes, runs Local Sync into the clean destination, then applies the stash with index state as the final layer. Ignored files remain in the source worktree and arrive through Local Sync when configured.
5. Starts the destination with strict Claude/Codex resume and waits up to 30 seconds for the real idle agent prompt. A failed resume must not start a fresh agent.
6. Persists removal from the source thread before killing its old tmux session, then navigates to the destination. The source tab is not added to closed-tab restore history.

All tabs in a thread share one worktree, so moving dirty state affects the whole source thread: remaining tabs see those working-tree changes disappear. Existing commits are shared branch history; the destination starts from the current commit, but Magent does not rewrite/reset the source branch to guess which commits belong to one tab. For a detached source worktree, resolve that worktree's exact HEAD hash instead of passing the ambiguous `HEAD` ref through the main repository.

Rollback is mandatory until source-tab removal succeeds. The recovery stash stays alive across destination worktree/session creation. If worktree setup, strict resume readiness, or source persistence fails, delete the destination session/worktree/branch first, reapply the stash with `--index` to the source, and leave the original tab running. A stash-drop failure after success is non-destructive and may leave only a redundant recovery stash.

Verify both that `git stash push` created the uniquely marked stash and that the source is clean afterward. A dirty submodule or nested repository may produce no stash or only a partial stash when mixed with ordinary edits; restore the transferable subset immediately and abort rather than reporting a partial move.

The stash marker durably records source/destination thread IDs, the source session, and the generated destination name. During startup, scan every project for these markers. If the source still owns the tab, remove any partial destination and restore the stash; if source persistence already removed the tab, the move committed and only the redundant stash should be dropped. This makes recovery independent of the in-memory transfer dictionary.

The destination session gets a new tmux identity, creation timestamp, worktree environment, and Ghostty surface. Never re-parent the live source tmux session: its process cwd and Magent environment still identify the old worktree/thread. If the source tab was detached, return its surface before the structural `TmuxService.killSession` barrier runs.

## Worktree Recovery

Automatic — when a user selects a thread whose worktree directory is missing, `SplitViewController` triggers recovery via `ThreadManager.recoverWorktree()`, showing progress via banners.

## Session Lifecycle

- **Stale tmux cleanup** is centralized in `SessionLifecycleService.cleanupStaleMagentSessions()` (forwarded via `ThreadManager`), scoped to `ma-` sessions only. Used for lifecycle hooks + session-monitor poller (5-minute cadence) instead of ad hoc `tmux kill-session` sweeps.
- **Dead session recreation is lazy**: `checkForDeadSessions` updates `thread.deadSessions` but only auto-recreates the currently visible session. Others stay dead until the user selects the tab → `ensureSessionPrepared` → `recreateSessionIfNeeded`. Never post `.magentTabWillClose` to clean up sessions that should be preserved — use `evictedIdleSessions` + `ReusableTerminalViewCache.evictSessions()` instead.
- **Recent-session fast path spans VC rebuilds**: `ThreadDetailViewController` records which sessions were restored from `ReusableTerminalViewCache` during `makeTerminalView(for:)`. `setupTabs(...)` restores the selected surface before constructing secondary terminal views and cancels the debounced overlay as soon as that selected surface is recovered. It then checks `ThreadStartupOverlayDecision` before loading-overlay agent-type probing, and `ensureSessionPrepared` passes the resource-backed state into `ThreadManager.isSessionPreparedFastPath(...)` before any tmux probe. The short `knownGoodSessionContexts` TTL remains a fallback when no reusable surface was retained. Dead, evicted, missing-from-thread, currently-recreating, or explicit startup-handoff sessions must always use the slow validation/recreation path.
- **Terminal surface reuse identity excludes mutable resume metadata**: cache compatibility is based on thread/session ownership, normalized worktree path, terminal-vs-agent role, agent type, and the session creation timestamp. Do not put the generated startup command or conversation/resume ID in this identity: those values may refresh while a live surface is detached and do not change whether that surface can be reattached safely. Every `TmuxService.killSession` pre-kill hook invalidates the cached entry before freeing Ghostty surfaces, so a recreated session cannot inherit the old view.
- **Terminal surface cache is count-configurable and pressure-aware**: `AppSettings.terminalSurfaceCacheLimit` controls overflow pruning. The default is 8 retained surfaces; `nil` means no count limit (surfaces still expire by `ReusableTerminalViewCache.maxIdleAge`). `Settings > Threads > Session Management` exposes this as "Limit cached terminal views" and immediately prunes overflow when lowered. Independently of that preference, a macOS memory-pressure warning keeps only the two newest detached surfaces and critical pressure releases all detached surfaces. Pressure trimming runs on the main actor, explicitly frees each Ghostty surface, and never kills the backing tmux session.
- **Slow non-agent tab switches must still show progress**: `startLoadingOverlayTracking(...)` should not immediately dismiss for plain terminal tabs. Keep the same debounced loading overlay active during `ensureSessionPrepared`/tmux validation so users get visible feedback when a switch takes longer than the fast path.
- **Startup-overlay retention must be agent-only**: after `setupTabs(...)` or `selectTab(...)` resolves the selected session, only keep the startup overlay alive when that tab still resolves to a live agent session. If runtime detection says the pane is back at a plain terminal, dismiss `Preparing terminal session...` immediately instead of honoring stale startup-overlay tokens.
- **Prepared-tab attach failures must degrade to visible recovery, never blank UI**: if `selectPreparedTab(...)` cannot attach/select the terminal view during startup or tab selection, keep the loading overlay visible with explicit diagnostic text and immediately retry through the full `selectTab(...)` path (`ensureSessionPrepared` / tmux validation) instead of returning silently.
- **Thread-switch startup overlay is primed in `viewDidLoad`**: `ThreadDetailViewController.viewDidLoad` calls `ensureLoadingOverlay()` and reveals a debounced (`0.25s`) "Loading thread..." overlay before the async `setupTabs(...)` task fires, so the view never renders as a blank page during the main-actor task hop. `setupTabs(...)` must dismiss or overwrite the label along every exit path — `showCreationOverlay` / `startLoadingOverlayTracking` overwrite the label, the non-terminal-only branch calls `dismissLoadingOverlay()`, and the terminal-path-with-non-terminal-restore branch must also dismiss after `selectTab(at: slotIndex)` because `startLoadingOverlayTracking` is skipped for that case. The debounce means warm fast-path switches never flash the overlay.
- **`setupTabs(...)` must be a full rebuild, not append-in-place**: before recreating tab items/slots from `thread.tmuxSessionNames` and persisted non-terminal tabs, clear existing `tabItems`, remove existing `terminalViews` from the view hierarchy, and reset web/draft view arrays. Partial rebuilds can leave stale tab UI entries and manifest as duplicate tabs after `.magentThreadsDidChange`.
- **The fixed Terminal slot must stay plain terminal content**: `setupTabs(...)` always reserves display index 0 for the non-closable Terminal tab and display index 1 for Diff. If a legacy/current thread only has agent sessions, register a plain fallback terminal session first and do not overwrite `lastSelectedTabIdentifier`; otherwise the agent can bind to the fixed Terminal slot and disappear from the movable tab list.
- **Tab hover status hints must be refreshed from the same notification paths as tab indicators**: tooltip text is derived from live thread/session state (busy, waiting, rate-limit, dead, keep-alive, unread markers). Any code path that updates tab badges, capsule treatments, or indicator dots must also refresh tab tooltips to avoid stale hover details.
- **Busy tabs use the shared capsule-border animator**: `TabItemView` replaces its inline spinner with the same rotating conic-gradient border used by sidebar thread capsules. Keep both surfaces routed through `BusyCapsuleBorderAnimator` so animation timing, selection colors, appearance updates, layout handling, and Reduce Motion behavior remain aligned.
- **New-tab completion must reconcile against current slots**: `addTab(...)` inserts a pending placeholder immediately, but `handleThreadsDidChange` can run `setupTabs(...)` before async session creation completes. Success handling must detect whether the created session is already present, should replace the pending placeholder, or should append, and then resolve selection/title by session name (not stale pending index).
- **Local create flow must own selection while auto-switch tab creation is in flight**: when the user creates a tab with "Switch to new tab" enabled (`Cmd+T` fast submit path included), suppress `handleThreadsDidChange`-triggered `setupTabs()` rebuilds until the local placeholder→session reconciliation finishes. Rebuild-driven re-selection during this window causes visible old/new tab bouncing.
- **Manual session cleanup** (`SessionLifecycleService`) must use the same eviction model as idle eviction: mark in `SessionTracker.evictedIdleSessions`, evict from cache before killing, never touch tab metadata. Protected sessions (busy, waiting, rate-limited, magent-busy, visible) must never be killed.
- **Async thread work must use stable IDs, never retained array indices**: `await` lets archive/delete or another background refresh remove and reorder `ThreadStore.threads`. Snapshot the thread value or `(id, sessions)` needed for I/O, then re-resolve with `ThreadStore.thread(byId:)`, `threadIndex(byId:)`, or `update(id:_:)` after every suspension point before reading or mutating live state. If the thread no longer exists, discard the stale result. This applies to monitor scans, model/conversation metadata refresh, branch and tab rename, session cleanup, worktree recovery/moves, and startup migrations.
- **Terminal corruption detection + repair** is transient/session-scoped:
  - Detection sources: Ghostty renderer health callbacks (`GHOSTTY_ACTION_RENDERER_HEALTH`) and periodic tmux pane replay-block checks (repeated tail-block fingerprint).
  - Session state lives in `SessionTracker.rendererUnhealthySessions` and `SessionTracker.replayCorruptedSessions`, surfaced through `ThreadManager.isTerminalCorrupted(sessionName:)`.
  - UI shows a warning indicator on affected tabs and a `Repair Terminal` action in the tab `Session` menu.
  - Repair must refuse when the session is busy, waiting for input, has unsubmitted input, or is in tmux copy-mode. When allowed, it kills/recreates only that session and clears corruption markers.
  - Corruption state must be re-keyed on session rename and pruned on tab/thread cleanup, same as other transient session-keyed state.
- **Resume metadata boundaries**: Claude/Codex resume lookup is keyed by worktree path, so when an archived auto-generated worktree name is reused, only conversations newer than the current thread's `createdAt` may be adopted.
- **tmux zombie overload recovery** is banner-driven: `ThreadManager.checkTmuxZombieHealth()` monitors zombie-heavy tmux parents and offers a one-click `restartTmuxAndRecoverSessions()` action.

## Thread Archive/Delete — Ghostty Surface Teardown

Archiving or deleting a thread must free every `ghostty_surface_t` owned by the thread **before** any `tmux kill-session` runs, or libghostty calls `_exit()` when a PTY closes on a live surface and kills the whole app. This is the same invariant as tab-close, but at thread scope, so the teardown has to cover three hierarchies:

1. `ReusableTerminalViewCache` (preserved detached surfaces).
2. The main-window `ThreadDetailViewController` (in-view surfaces of the currently selected thread).
3. Pop-out windows owned by `PopoutWindowManager` — both thread-level (`ThreadPopoutWindowController`) and tab-level (`TabPopoutWindowController`).

Required sequence before any tmux kill: evict cache -> return pop-outs -> evict cache again -> swap detail VC to empty state. Archive may then continue cleanup in a detached task because it is the soft action and keeps an archived record. Delete is the hard action: it must await worktree removal and branch deletion, verify the worktree path is gone, and only then remove the thread from persistence/UI. Both archive and delete must post `.magentArchivedThreadsDidChange`; the notification is load-bearing because `PopoutWindowManager` only learns the thread is gone via that observer. `deleteThread` must post it too — `didDeleteThread` alone is not enough.

See `docs/agent-runtime/libghostty-integration.md` → "Surface Lifecycle: Thread Archive/Delete Contract" for the full rationale, code sketch, and the `preserveSurfaceOnDetach` gotcha that makes the second cache eviction mandatory.

## Startup Recovery

If `threads.json` records are reassigned onto an existing project during `settings.json` recovery, do not keep multiple active threads that resolve to the same normalized `worktreePath`. Merge their tabs/state into one canonical thread and de-duplicate terminal tab titles (especially for the main worktree).

Before the first live status refresh completes, launch restores the last-known Jira, PR/MR, dead-session, and intentionally-evicted-session state from cache. This keeps the initial sidebar visually stable across relaunches. The cache is display-only: Jira/PR sync and `checkForDeadSessions` remain authoritative and replace stale values after launch. Hidden-thread state is not duplicated in this cache because it is already authoritative in `threads.json`.
