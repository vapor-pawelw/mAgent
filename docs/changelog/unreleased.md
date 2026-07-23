## Unreleased

### Appearance

#### Features

- Customize Magent's primary color from Appearance settings, with app highlights and default user chat bubbles staying in sync.

### Settings

#### Improvements

- Added a clearly destructive Remove Project action at the bottom of each project's settings.

#### Bug Fixes

- Fixed clicking another project in Settings leaving the previous project's details on screen.

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

- Kept Terminal and Diff tabs visible beside thread actions while user-created tabs use the flexible, scrollable space to their left.
- Matched busy and completed tabs to their sidebar thread capsules with animated busy borders and green completion backgrounds.
- Codex chat tabs now show the selected model and reasoning effort in their names, with a clear Chat suffix; unfinished Claude chat entry points are hidden for now.
- Reopen cached recent threads immediately more often and let users tune how many terminal views Magent keeps for fast switching.
- Automatically give agent tabs a concise AI-generated name from their prompts, retrying after transient failures while preserving every manually renamed tab.
- Added a toolbar reminder with a first-time hint to reopen dismissed lost-prompt recovery banners without discarding the saved prompt.
- Rounded the initial prompt input in the new thread and new tab sheets.

#### Bug Fixes

- Fixed automatic AI naming for new agent terminal tabs that show a default model and effort label.
- Fixed renaming a terminal tab unnecessarily reloading its terminal view.
- Fixed recent thread switches flashing a loading overlay even when the selected terminal session was already cached and healthy.
- Fixed lost-prompt recovery controls showing a generic button label, kept recovery banners out of the toolbar area, added confirmation before discarding recovered prompts, and made `Esc` dismiss banners that show an `X`.

### Terminal

#### Bug Fixes

- Fixed terminal content scaling after moving a window between displays with different Retina scaling.

### Sidebar

#### Features

- Added a disabled-by-default Threads setting for showing worktree folder names on the second line of sidebar rows.
- Added collapsed-by-default hidden-thread groups that can be expanded independently in each sidebar section or project.
- Added toolbar and empty-state repository actions for creating, importing, or cloning repositories.
- Replaced thread activity durations with compact indicators: a colored spinner for long-running busy threads and a `zzz` symbol for stale threads, with the existing hover details and quick actions.
- Made sidebar status items right-clickable while preserving left-click thread selection, including direct numbered PR/MR opening, the full Jira menu, quick Hide and Archive actions from stale indicators, precise Stale/Busy context, and quick menus for priority, favorite, pinned, and hidden states.

#### Improvements

- Reduced the sidebar's minimum width so it takes less space on small screens.
- Moved thread signs inline before descriptions for a cleaner, more compact sidebar presentation, with signs dimming together with inactive thread text and a matching status icon identifying threads whose tmux sessions are stopped.
- Tightened spacing between sidebar threads while preserving stronger pinned, hidden, and section boundaries.
- Keep last-known PR/MR, Jira, hidden-thread, and stopped-session sidebar state visible immediately after relaunch while fresh checks run.
- Mark the priority matching a thread's Jira ticket in sidebar priority menus.
- Simplified section headers to plain rows and moved their color cue to diagonal top-right bands on thread capsules.
- Matched main-worktree capsules to the neutral thread background and kept a compact, optically aligned home icon inline when other thread icons are hidden.
- Reordered thread status rows so priority, Jira, and PR workflow details lead while local state icons and activity trail; explicit Keep Alive shields now remain visible on pinned threads.
- Anchored sidebar status rows closer to the bottom edge of thread capsules for clearer separation from branch and description text.
- Improved compact activity, PR/MR, Jira, and section-count indicator readability with higher-contrast appearance-aware colors.
- Aligned pinned, favorite, and hidden sidebar markers, matched them to thread-description color and dimming, and reduced the visual weight of pinned/favorite icons.
- Replaced sidebar dividers between pinned, normal, and hidden threads with cleaner spacing.
- Tightened Hidden disclosure spacing while preserving separation from the next section when collapsed.
- Added a default `Cmd+J` shortcut and View menu action to recenter the sidebar on the current thread.
- Keep moved or missing repositories visible with recovery and discard actions.
- Refresh missing-repository status when Magent returns to the foreground.
- Center the missing-repository recovery row content within its sidebar box.
- Made default thread pills subtler in dark mode while keeping them lighter than the sidebar.
- Removed the passive outline from busy thread rows so only their animated border arc is visible.
- Sticky sidebar headers now use a stronger live blur instead of an opaque fill.
- Hid the thread-list scrollbar so it no longer cuts through sticky header blur.
- Added consistent breathing room above the first repository header and between repository headers and main worktree rows.
- Made compact thread rows the default and replaced the old `Narrow threads` setting with an opt-in `Wide threads` setting.
- Added a Threads setting to show sidebar thread icons; existing installations keep them hidden until enabled.
- Added an **Archive All Threads...** action to section header context menus when a section contains threads.

#### Bug Fixes

- Fixed sidebar drag-and-drop so threads can move into empty sections and can be placed immediately above collapsed hidden threads.
- Fixed Magent crashing during startup while constructing the main sidebar and content split view.
- Kept dirty-branch dots orange when their sidebar thread is selected.
- Fixed main worktree branch text clipping and kept status-free sidebar thread rows from stretching their text layout.
- Kept stale-activity badges off main worktrees.
- Kept consistent spacing between thread descriptions and their branch line when PR or Jira status badges are present.
- Kept the sidebar width stable during thread selection without interfering with manual divider dragging.
- Kept the first repository's normal header and collapse control usable at the top of the sidebar before sticky headers activate.
- Removed the unintended trailing area beneath sticky repository and section headers.
- Fixed trailing thread status icons following the text width instead of aligning to the sidebar row's trailing content edge, and kept archive suggestions centered on the text without overlapping the spaced status row.
- Updated all sidebar tickets immediately when allowed Jira prefixes change, without an unnecessary network refresh.
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
