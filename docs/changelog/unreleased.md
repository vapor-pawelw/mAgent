## Unreleased

### Agents

#### Improvements

- Added Fable as the top Claude model and default review model.
- Added a Codex Fast mode lightning toggle to new thread and tab launch sheets.
- Added a `start-agent` helper in Magent terminals so users can relaunch or resume a tab's configured agent after it exits, and recovery banners now use the short helper instead of injecting the full startup command.

#### Bug Fixes

- Stopped Magent-launched Codex tabs from showing the deprecated `features.codex_hooks` warning when the user's Codex config still uses the old key.

### Thread

#### Improvements

- Reopen cached recent threads immediately more often and let users tune how many terminal views Magent keeps for fast switching.
- Added a toolbar reminder with a first-time hint to reopen dismissed lost-prompt recovery banners without discarding the saved prompt.
- Rounded the text inputs in the new thread and new tab sheets.

#### Bug Fixes

- Fixed recent thread switches flashing a loading overlay even when the selected terminal session was already cached and healthy.
- Fixed lost-prompt recovery controls showing a generic button label, kept recovery banners out of the toolbar area, added confirmation before discarding recovered prompts, and made `Esc` dismiss banners that show an `X`.

### Terminal

#### Bug Fixes

- Fixed terminal content scaling after moving a window between displays with different Retina scaling.

### Sidebar

#### Features

- Added toolbar and empty-state repository actions for creating, importing, or cloning repositories.

#### Improvements

- Keep moved or missing repositories visible with recovery and discard actions.
- Refresh missing-repository status when Magent returns to the foreground.
- Center the missing-repository recovery row content within its sidebar box.
- Made the thread-list background slightly darker in dark mode.
- Sticky sidebar headers now use a stronger live blur instead of an opaque fill.
- Hid the thread-list scrollbar so it no longer cuts through sticky header blur.
- Added breathing room between repository headers and main worktree rows.
- Made compact thread rows the default and replaced the old `Narrow threads` setting with an opt-in `Wide threads` setting.
- Added a Threads setting to hide sidebar thread icons and reclaim their row space.
- Added an **Archive All Threads...** action to section header context menus when a section contains threads.

#### Bug Fixes

- Fixed section-header `Rename Section` context-menu actions failing to enter inline rename mode.
- Prevented newly created thread selection from being undone by stale sidebar scroll restores.
- Fixed collapsed sidebar sections corrupting row geometry after reloads, which could leave huge gaps or overlap project and section headers.
- Fixed sidebar rows and headers overlapping during new-thread creation.
- Fixed sticky section headers not blurring the sidebar content underneath.
- Fixed sticky repository headers disappearing in the gap before the next repository header takes over.
- Kept the add-thread `+` button visible on sticky repository headers.
- Fixed sidebar thread clicks getting ignored after interrupted drag interactions.
- Fixed the sidebar add-repository menu so create and import actions open reliably.
