## Unreleased

### CLI

#### Features
- Added `magent-cli pin-tab` and `unpin-tab` for pinning or unpinning any movable tab by tab index or session name, with pinned state now persisted for draft and chat tabs.

### Sidebar

#### Features
- Moved the main-window thread strip into the window toolbar, including its PR/Jira actions, while keeping the tabs bar in the thread view and leaving pop-out windows unchanged.

#### Bug Fixes
- PR/MR badges now keep the last confirmed link through failed syncs and app relaunches, dimming stale metadata instead of removing it until a later successful sync confirms the current state.
- Diff file headers now show rename-only changes with a `RENAMED` badge, keep binary-only changes visible with a `BINARY` label and centered unavailable placeholder, and expose hidden context at the start and end of displayed hunks.
- Agent completion now refreshes the active thread's changes panel and Diff tab state immediately instead of waiting for the next git-status polling tick.
- Fixed Diff tabs timing out when a worktree contains large or binary untracked files.
- Fixed Delete hiding threads before their worktree and branch were actually removed, which could let the worktree reappear after restart.

### Status Bar

#### Features
- The bottom status bar now expands favorite, completed, and waiting thread statuses into compact clickable thread badges when there is enough room, then falls back to the existing count badges when space gets tight.
- Inline thread badges now support right-click actions to clear completed work or remove favorites, while status glyphs keep the collapsed status item click and context-menu behavior.
- Inline favorite badges can now be dragged to reorder Favorites and can use a saved status-bar alias for shorter labels.
- Rate-limited, busy, and popped-out thread status items stay compact near the trailing side without displacing sync status from the right edge.

#### Improvements
- Busy and waiting status badges now use clearer filled glyphs in the bottom status bar.

#### Bug Fixes
- The bottom status bar now separates session counts from thread status badges and refreshes persisted thread statuses immediately on launch.
- Inline status-bar thread badges now respond to clicks reliably and focus popped-out thread or tab windows directly when their status is selected.
- Inline status-bar thread badges now stay expanded until the measured fixed status-bar controls actually leave too little room.
- Thread navigation now reopens already-selected dead-session threads and forces dead terminal sessions through the lazy recreation path.
