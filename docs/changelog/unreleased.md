## Unreleased

### Settings

#### Improvements

- Added a clearly destructive Remove Project action at the bottom of each project's settings.

### Agents

#### Improvements

- Added Fable as the top Claude model and default review model.
- Added GPT 5.6 Sol, Terra, and Luna to Codex model choices, including their `none` and `max` reasoning options, and made GPT 5.6 Sol with low reasoning the default Codex launch choice.
- Added a Codex Fast mode lightning toggle to new thread and tab launch sheets.
- Added a `start-agent` helper in Magent terminals so users can relaunch or resume a tab's configured agent after it exits, and recovery banners now use the short helper instead of injecting the full startup command.

#### Bug Fixes

- Stopped Magent-launched Codex tabs from showing the deprecated `features.codex_hooks` warning when the user's Codex config still uses the old key.

### Thread

#### Improvements

- Reopen cached recent threads immediately more often and let users tune how many terminal views Magent keeps for fast switching.
- Added a toolbar reminder with a first-time hint to reopen dismissed lost-prompt recovery banners without discarding the saved prompt.
- Rounded the initial prompt input in the new thread and new tab sheets.

#### Bug Fixes

- Fixed recent thread switches flashing a loading overlay even when the selected terminal session was already cached and healthy.
- Fixed lost-prompt recovery controls showing a generic button label, kept recovery banners out of the toolbar area, added confirmation before discarding recovered prompts, and made `Esc` dismiss banners that show an `X`.

### Terminal

#### Bug Fixes

- Fixed terminal content scaling after moving a window between displays with different Retina scaling.

### Sidebar

#### Features

- Added collapsed-by-default hidden-thread groups that can be expanded independently in each sidebar section or project.
- Added toolbar and empty-state repository actions for creating, importing, or cloning repositories.
- Replaced the thread activity pill with a cumulative, color-coded circle and made its Circle/Text style switch available directly from the indicator.
- Made priority, favorite, pinned, and hidden sidebar badges directly actionable with their matching quick menus.

#### Improvements

- Restyled section headers with compact colored leading rails and balanced content padding so section boundaries are clearer without competing with thread cards.
- Moved thread activity, priority, and status indicators into clearer bottom-left and bottom-right sidebar stacks, including a subdued hidden-thread marker.
- Replaced sidebar dividers between pinned, normal, and hidden threads with cleaner spacing.
- Tightened Hidden disclosure spacing while preserving separation from the next section when collapsed.
- Added a default `Cmd+J` shortcut and View menu action to recenter the sidebar on the current thread.
- Keep moved or missing repositories visible with recovery and discard actions.
- Refresh missing-repository status when Magent returns to the foreground.
- Center the missing-repository recovery row content within its sidebar box.
- Made default thread pills subtler in dark mode while keeping them lighter than the sidebar.
- Removed idle thread-capsule outlines for a cleaner sidebar.
- Removed the passive outline from busy thread rows so only their animated border arc is visible.
- Sticky sidebar headers now use a stronger live blur instead of an opaque fill.
- Hid the thread-list scrollbar so it no longer cuts through sticky header blur.
- Added breathing room between repository headers and main worktree rows.
- Made compact thread rows the default and replaced the old `Narrow threads` setting with an opt-in `Wide threads` setting.
- Added a Threads setting to hide sidebar thread icons and reclaim their row space.
- Added an **Archive All Threads...** action to section header context menus when a section contains threads.

#### Bug Fixes

- Made secondary sidebar thread metadata 20% dimmer, with an additional proportional dimming for inactive threads and hidden rows.
- Fixed the sidebar icon visibility setting so changing it updates thread rows immediately.
- Fixed idle sidebar thread-duration tooltips incorrectly claiming the thread was busy; they now show the last activity time.
- Fixed section-header `Rename Section` context-menu actions failing to enter inline rename mode.
- Fixed a crash that could happen after archiving or deleting the selected thread.
- Prevented newly created thread selection from being undone by stale sidebar scroll restores.
- Fixed collapsed sidebar sections corrupting row geometry after reloads, which could leave huge gaps or overlap project and section headers.
- Fixed sidebar rows and headers overlapping during new-thread creation.
- Fixed sticky section headers not blurring the sidebar content underneath.
- Fixed sticky repository headers disappearing in the gap before the next repository header takes over.
- Kept the add-thread `+` button visible on sticky repository headers.
- Fixed the add-thread `+` button on sticky repository headers not responding to clicks.
- Fixed sidebar thread clicks getting ignored after interrupted drag interactions.
- Fixed the sidebar add-repository menu so create and import actions open reliably.
