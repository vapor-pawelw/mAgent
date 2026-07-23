# Settings Categories

## User-facing behavior

- App-wide preferences stay in `Settings > General`.
- Appearance and color preferences live in `Settings > Appearance`.
- Terminal-specific preferences now live in `Settings > Terminal`.
- Thread-focused preferences now live in `Settings > Threads`.
- `General` currently owns update controls, archive defaults, the keyboard shortcuts reference card, the Data Backup backup/restore card, and the environment-variable reference used by startup injection settings.
- `Appearance` owns app/terminal light-dark appearance, the app primary color, and the "Don't override agent color theme" toggle.
- `Terminal` owns Ghostty mouse-wheel override behavior and terminal overlay visibility toggles.
- `Threads` owns thread naming defaults, thread sections, recently archived thread restore history, startup injection fields, the review prompt, sidebar display options (wide threads, thread icons, optional worktree names, PR/Jira status badge toggles, busy/idle duration toggle), and session management (idle session eviction limit, terminal surface cache limit, and "Protect pinned threads and tabs from eviction" toggle).
- Section color editing now reuses a single system color picker per settings screen, so switching to another section keeps the earlier section's custom dot color intact instead of resetting it.
- Changing the primary color updates Magent's primary actions, selections, highlights, and brand accents across open windows. Chat user bubbles follow it whenever they do not have a custom bubble-color override; resetting chat colors restores that relationship.
- Debug-only features may still appear in Settings during local development, but they should be clearly annotated with `Debug builds only` and fully hidden from release builds.
- A dedicated `Debug` sidebar category exists in debug builds only (`#if DEBUG`). It currently exposes "Reset Onboarding State" (clears `isConfigured` and offers to relaunch), "Relaunch App", and an `Experimental` card with `Chats` plus `Enable tab detaching` toggles (both off by default). Add new developer utilities here rather than sprinkling ad-hoc debug actions into other panes.

## What Changed In Recent Threads

### Debug category (improve-onboarding thread)
- Added a `Debug` sidebar category visible only in `#if DEBUG` builds: `SettingsDebugViewController.swift`.
- Actions: "Reset Onboarding State" (clears `isConfigured`, offers immediate relaunch) and "Relaunch App".
- Wired into `SettingsSplitViewController` with `#if DEBUG` guards on the VC declaration, `setupDetailContainer`, and `showCategoryContent`.

### Settings categories split (previous thread)
- Added a new `Threads` sidebar category in the settings window.
- Added a new `Terminal` sidebar category in the settings window.
- Moved thread-related controls out of the crowded `General` pane into a dedicated controller.
- Moved terminal overlay toggles out of `General` and into `Terminal`, alongside appearance and wheel-behavior controls.
- Added one shared appearance setting that drives both AppKit chrome and the embedded Ghostty terminal.
- Tightened section color picker ownership in both section editors so only one shared picker is active and changing focus between rows does not write the new color back into the previously edited section.
- Added a `Recently Archived` card to `Settings > Threads` that lists up to 10 archived threads and provides inline restore actions.

### Data backup restore (auto-backup-critical-config)
- Added a `Data Backup` card to `Settings > General` with `Back Up Now` and `Restore from Backup…` actions.
- Magent now keeps rolling `.bak` copies of `threads.json`, `settings.json`, and `agent-launch-prompt-drafts.json` before overwriting them, and also writes 30-minute snapshot directories under Application Support.
- The `Data Backup` card shows the most recent snapshot timestamp so users can see when the last backup was created.
- Restore now lists both periodic snapshots and pre-restore safety backups, then relaunches the app after replacing the current persistence files.
- If the selected snapshot is partial, missing files are left untouched instead of being deleted during restore.
- On launch, Magent may recover `settings.json` from the best available recovery candidate (rolling backup or periodic snapshot) when active thread data exists but the current settings file is missing, empty, or no longer covers every project referenced by active threads.
- If startup still sees active-thread project IDs missing from the loaded settings, writes to `settings.json` stay blocked for that launch so a stale/default Settings window cannot save an empty projects list over the recoverable state.

## Implementation Notes

- Category registration and the sidebar/detail controller wiring live in `Magent/Views/Settings/SettingsViewController.swift`.
- `Magent/Views/Settings/SettingsGeneralViewController.swift` is intentionally limited to app-level preferences.
- The backup actions are coordinated from `SettingsGeneralViewController`, but restore must first stop background pollers and block writes for the restorable persistence files before `BackupService.restoreSnapshot(_:)` swaps files on disk. The manual snapshot button can call `BackupService.createSnapshot()` directly because it only reads the current persistence files.
- The Data Backup status line is driven by `BackupService.listSnapshots()` and refreshes when `magentBackupSnapshotsDidChange` is posted after a new snapshot is created.
- Settings panes that edit global preferences must reload the latest `AppSettings` from persistence immediately before saving each UI change. Holding an old in-memory snapshot and writing it back wholesale is unsafe after backup restores or startup recovery because it can drop newer project registrations.
- `Magent/Views/Settings/SettingsTerminalViewController.swift` owns terminal-scoped preferences and posts `magentSettingsDidChange` so open windows update immediately.
- `Magent/Views/Settings/SettingsThreadsViewController.swift` owns thread-scoped preferences, and `Magent/Views/Settings/SettingsThreadsViewController+Sections.swift` owns the thread-sections table behavior.
- `AppSettings.isTabDetachFeatureEnabled` is the effective gate for tab detaching. It always returns `false` in release builds and mirrors the debug-only persisted flag (`experimentalEnableTabDetach`) only under `#if DEBUG`.
- `AppSettings.experimentalEnableChats` gates chat-surface creation options in debug settings and the dedicated `Chat` settings sidebar category. Existing persisted chat tabs can still render; the toggle controls whether new chat entries are offered from agent menus while the feature is being held locally.
- The recently archived list reads from persisted threads, sorts by `archivedAt`, and listens for a shared archive-state notification so it refreshes while Settings is open.
- Project overrides use the parallel section editor in `Magent/Views/Settings/SettingsProjectsViewController.swift` and `Magent/Views/Settings/SettingsProjectsViewController+Sections.swift`.
- A selected project's settings end with a destructive `Remove Project…` button. It uses the same confirmed removal action as the minus button below the project list and does not delete the repository from disk.
- Project-list selection callbacks must resolve the detail project from the table's newly selected row. `currentProjectID` tracks the detail already on screen and must not override a new click.
- Both section editors use `NSColorPanel.shared`, so they must set the active `sectionId` and temporarily detach target/action before assigning `panel.color`, then restore the callback after the programmatic update.
- App appearance is applied centrally from `AppDelegate`: `NSApp.appearance` controls the AppKit chrome, and Ghostty receives the matching light/dark preference through `GhosttyAppManager`.
- `AppTheme` owns the resolved runtime primary color. Apply a new settings snapshot before broadcasting `magentSettingsDidChange`, so view refresh observers never read the previous cached color.
- Keep semantic status colors such as errors, warnings, Jira states, priorities, and pop-out purple independent from the customizable primary color.

## Appearance Mode Switch Gotchas

When appearance changes (`NSApp.appearance` is reassigned), CALayer `backgroundColor` and `borderColor` set as `CGColor` do **not** auto-update — they are fixed values baked in at assignment time. Views that rely on asset-catalog colors for their layer must re-resolve inside `viewDidChangeEffectiveAppearance` using:

```swift
override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    effectiveAppearance.performAsCurrentDrawingAppearance {
        layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
    }
}
```

Without `performAsCurrentDrawingAppearance`, calling `.cgColor` on a dynamic `NSColor` may resolve against the previous (wrong) appearance. See `SettingsSectionCardView` and `AppBackgroundView` (in `ThreadDetailViewController.swift`) for reference implementations.

For views whose appearance cannot be caught via `viewDidChangeEffectiveAppearance` (e.g. `NSViewController` subclasses, which do not have this hook), use a dedicated `NSView` subclass as the backing view and override the hook there.

## Gotchas

- Keep `General` and `Threads` split by user mental model, not by which `AppSettings` fields happen to sit near each other in the model.
- Terminal-visible preferences belong in `Terminal`, even when they affect all threads globally.
- Thread-sections editing logic moved with the `Threads` controller; avoid reintroducing section-table actions into `SettingsGeneralViewController`.
- `NSColorPanel.shared` is process-wide. Programmatically setting its color can synchronously fire the current action, so if you do not clear/rebind the target around that assignment, the previously edited section can absorb the new color change.
- When a feature is release-gated behind a `FEATURE_*` flag, hide its sidebar category/card entirely in release builds instead of showing disabled controls that cannot work.
- The app appearance selector is the source of truth for both AppKit and the embedded terminal. Do not add a separate terminal-only light/dark selector unless the product deliberately supports mixed chrome/terminal appearance.
- The "Don't override agent color theme" checkbox (`AppSettings.preserveAgentColorTheme`) gates three things: (1) the Claude settings JSON (`/tmp/magent-claude-hooks.json`) won't include `theme`/`terminalTheme` keys, (2) Claude won't get `TERM=screen COLORTERM=` prepended in light mode, and (3) Codex won't get `-c tui.theme="ansi"` in light mode. The Claude hooks settings cache key includes a `-notheme` suffix when the toggle is on, so the file is regenerated correctly when the setting changes between sessions.
- Codex sessions inherit `NO_COLOR` from the parent environment. Magent should not override this; users who explicitly export `NO_COLOR=1` get no-color Codex output, while default environments (without `NO_COLOR`) keep color output.
- Snapshot restore is not safe as a raw file copy while the app is live. Before restoring, stop the session monitor/update poller/backup timer, cancel pending debounced thread saves, and block writes for every restorable file. Otherwise a background save can immediately overwrite the restored snapshot or interleave with it.
