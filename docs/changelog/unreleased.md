## Unreleased

### Agents

#### Improvements

- Added Fable as a selectable Claude model.
- Added a `start-agent` helper in Magent terminals so users can relaunch or resume a tab's configured agent after it exits, and recovery banners now use the short helper instead of injecting the full startup command.

### Thread

#### Improvements

- Reopen cached recent threads immediately more often and let users tune how many terminal views Magent keeps for fast switching.
- Added a toolbar reminder with a first-time hint to reopen dismissed lost-prompt recovery banners without discarding the saved prompt.

#### Bug Fixes

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
- Sticky sidebar headers now use a stronger live blur instead of an opaque fill.
- Hid the thread-list scrollbar so it no longer cuts through sticky header blur.
- Added breathing room between repository headers and main worktree rows.

#### Bug Fixes

- Prevented newly created thread selection from being undone by stale sidebar scroll restores.
- Fixed project headers overlapping earlier sidebar sections and leaving a gap before the main worktree after creating threads.
- Fixed sticky section headers not blurring the sidebar content underneath.
- Fixed sticky repository headers disappearing in the gap before the next repository header takes over.
- Kept the add-thread `+` button visible on sticky repository headers.
- Fixed sidebar thread clicks getting ignored after interrupted drag interactions.
- Fixed the sidebar add-repository menu so create and import actions open reliably.
