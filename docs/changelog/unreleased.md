## Unreleased

### Appearance

#### Features

- Customize Magent's primary color from Appearance settings across thread and tab creation actions, tab toolbar controls, Settings selections, buttons, and sliders, app highlights, and default user chat bubbles.

### Settings

#### Improvements

- Added a clearly destructive Remove Project action at the bottom of each project's settings.

#### Bug Fixes

- Fixed clicking another project in Settings leaving the previous project's details on screen.

### Agents

#### Improvements

- Added Fable as the top Claude model and default review model.
- Added GPT 5.6 Sol, Terra, and Luna to Codex model choices, including their `none` and `max` reasoning options, Ultra for Sol and Terra, and GPT 5.6 Sol with low reasoning as the default Codex launch choice.
- Added a Codex Fast mode lightning toggle to new thread and tab launch sheets.
- Added a `start-agent` helper in Magent terminals so users can relaunch or resume a tab's configured agent after it exits, and recovery banners now use the short helper instead of injecting the full startup command.

#### Bug Fixes

- Kept the Start Agent recovery banner off terminal-only tabs and prevented it from flashing during normal agent startup.
- Kept Codex tabs visibly busy while MCP servers start, even when Codex shows its composer at the same time.
- New Codex threads now wait for startup activity to finish before submitting their initial prompt, preventing it from becoming a queued follow-up.
- Fixed completed background Codex tabs sometimes remaining busy until opened by recognizing when a newer idle prompt supersedes stale activity text.
- Stopped Magent-launched Codex tabs from showing the deprecated `features.codex_hooks` warning when the user's Codex config still uses the old key.

### Thread

#### Features

- Move an idle Claude or Codex tab into a newly created thread while preserving its exact conversation, tab name and settings, and the current worktree's staged, unstaged, and untracked changes, with guided crash recovery that only offers Retry for safe cleanup.
- Unified new and forked thread creation with a context-aware visual source picker for starting from the main worktree, another thread, or any branch.
- Added `magent-cli finish-thread` to safely merge, optionally push, and archive any managed thread across registered repositories while leaving repository-specific preparation to caller-owned workflows.
- Pin the prompt Table of Contents beside terminal and chat content, browse newest-first high-contrast numbered rows with roomier pinned previews, then resize or detach the split while terminal content immediately reclaims the available width.
- Prompt Table of Contents rows now keep showing their cached relative start time and worked duration after terminal history rolls over, with exact timing and navigation availability on hover.

#### Improvements

- Prompt context menus now distinguish thread and tab renaming, with clearer prompt-based thread rename wording and one-click tab naming.
- Show a truncated initial prompt as a new thread's description immediately, use `Thread #N` when no prompt is provided, and still allow AI naming to replace either provisional title later.
- Hide icon controls and skip work-type classification during AI rename when automatic thread icons are disabled.
- Kept Terminal and Diff tabs visible beside thread actions while user-created tabs use the flexible, scrollable space to their left.
- Matched busy and completed tabs to their sidebar thread capsules with animated busy borders and green completion backgrounds.
- Codex chat tabs now show the selected model and reasoning effort in their names, use a clear Chat suffix, and support automatic naming from the first prompt; unfinished Claude chat entry points are hidden for now.
- Reopen cached recent threads immediately more often, automatically release detached terminal views when macOS reports memory pressure, and let users tune the normal cache limit.
- Automatically give agent tabs a concise AI-generated name from their prompts, with a primary-color title pulse while generation runs, retries after transient failures, isolation from unrelated Codex MCP startup failures, and protection for every manually renamed tab.
- Added a toolbar reminder with a first-time hint to reopen dismissed lost-prompt recovery banners without discarding the saved prompt.
- Rounded the initial prompt input in the new thread and new tab sheets.

#### Bug Fixes

- Made Escape cancel new thread and new tab prompt sheets while the prompt editor is focused.
- Softened the Table of Contents header and resize divider, added breathing room above the first prompt, and kept the known prompt count visible during refreshes.
- Prevented stale AI rename error banners after deleting, archiving, or otherwise removing a thread while its rename was still running.
- Kept PR and Jira action titles readable on one line when the window toolbar is narrow.
- Prevented simultaneous thread archives from racing on the main worktree, Local Sync files, or git metadata, with queued agent workflows now reporting the active thread and their live queue position.
- Kept the prompt Table of Contents populated without duplicating transient live renderings of cached prompts, refreshed it periodically and after Escape steering, and made prompt jumps remain accurate after terminal history rolls over.
- Kept the permanent Terminal and Diff tabs in their trailing positions even when restored agent or content tabs appear first in persisted session order.
- Fixed automatic AI naming for additional agent terminal tabs whose duplicate default or model/effort labels receive a numeric suffix.
- Fixed renaming a terminal tab unnecessarily reloading its terminal view.
- Fixed recent thread switches flashing or lingering on a loading overlay when mutable agent resume metadata changed even though the selected terminal session was still cached and healthy.
- Fixed lost-prompt recovery controls showing a generic button label, kept recovery banners out of the toolbar area, added confirmation before discarding recovered prompts, and made `Esc` dismiss banners that show an `X`.

### Chat

#### Improvements

- Right-click any text message to copy it or generate a concise tab name from its content.
- Refined Codex chats with a centered reading column, starter prompts, copyable code cards, state-aware controls, timed activity timelines, hover actions, and a counted jump-to-latest control.
- Added a live chat theme preview with contrast checks for user messages, assistant text, and status backgrounds.
- Kept long Codex chats responsive while replies stream, drafts are typed, and older transcript pages are browsed.
- Render chat headings, lists, quotes, separators, and fenced code as formatted content instead of raw Markdown.
- Keep all collapsed and expanded tool activity at a stable readable width with compact single-line headers.
- Matched the chat composer’s prompt surface to the rounded input used when creating threads and tabs.
- Made assistant replies easier to read with a wider unboxed layout while keeping user prompts and important statuses visually distinct.
- Replaced the animated working bubble with a quieter inline progress row.
- Moved per-message timestamps and model metadata into clear, borderless hover details to make conversations denser and easier to scan.
- Unified the message composer into a cleaner rounded input surface with an integrated attachment, model, reasoning, and send footer.
- Show patch edits in chat as clean changed-file links that open the focused diff instead of rendering raw patch/output text.
- Compacted consecutive chat activity rows into a collapsed expandable summary with clear system icons so restored agent work is easier to scan.
- Made chat tool activity cleaner by showing concise action summaries and keeping successful tool output collapsed by default.
- Hid internal command transport settings and kept command results from replacing useful action summaries with arbitrary output text.
- Show chat cancellations, errors, and approval-blocked Codex turns as clearer status bubbles.

#### Bug Fixes

- Fixed image attachments in Codex chat tabs being rejected before the agent could inspect them.
- Show live parallel-agent progress and tool activity in Codex chat tabs instead of leaving the conversation on `Working` until the delegated task finishes.
- Replaced the misleading long-running `Starting Codex` chat status as soon as Codex begins working.
- Kept Codex chat permissions in sync with Agent Settings when continuing an existing conversation, and prevented Sandbox Auto chats from getting stuck on approval requests they cannot answer.
- Prevented background tab refreshes from falsely cancelling active chats or leaving their Working timer running, and clarified compact Agent activity labels.
- Kept loading a Codex chat tab from expanding the Magent window to its maximum width.
- Prevented failed or approval-blocked Codex turns from replaying the same prompt, preserved steering messages that race with completion, stopped queued prompts after closing or clearing a chat, and blocked overlapping GUI/CLI turns from corrupting one conversation.
- Preserved model-change markers, local chat statuses, repeated-message identity, timestamps, attachments, and model metadata when restoring Codex transcripts.
- Reused warmed Codex chat processes between prompts so later replies no longer wait for integrations to initialize again.
- Kept chat tabs in their chosen position when switching threads or renaming tabs, aligned CLI tab indexes with that visible order, and preserved pinning and selection when closing or restoring chats.
- Kept `/help` reasoning choices aligned with every effort level supported by the selected Codex model.
- Fixed Codex’s no-reasoning option being labeled `Fast` in chat controls.
- Fixed Codex chat tabs crashing when restored activity summaries contained multiple icon rows.
- Keep failed or still-running tools and action-required chat statuses visible instead of hiding them inside collapsed activity summaries.
- Fixed `Continue in...` from a Codex chat showing only Claude Code instead of including and preferring the configured Codex default, and made terminal/chat choices open the selected surface.
- Kept the model shown by restored legacy chat tabs in sync with the model used for their next request.

### Terminal

#### Bug Fixes

- Fixed terminal content scaling after moving a window between displays with different Retina scaling.

### Sidebar

#### Features

- Made traditional mouse-wheel scrolling feel fluid while preserving native trackpad behavior and Reduce Motion preferences.
- Added a disabled-by-default Threads setting for showing worktree folder names on the second line of sidebar rows.
- Added collapsed-by-default hidden-thread groups that can be expanded independently in each sidebar section or project.
- Added toolbar and empty-state repository actions for creating, importing, or cloning repositories.
- Replaced thread activity durations with compact indicators: a colored spinner for long-running busy threads and a `zzz` symbol for stale threads, with the existing hover details and quick actions.
- Made sidebar status items right-clickable while preserving left-click thread selection, including direct numbered PR/MR opening, the full Jira menu, quick Hide and Archive actions from stale indicators, precise Stale/Busy context, and quick menus for priority, favorite, pinned, and hidden states.

#### Improvements

- Moved a more compact Add Repository control to the trailing edge of the sidebar titlebar, with the remaining area supporting native window dragging and double-click maximize/restore.
- Extended the sidebar beneath the standard macOS controls, showing one seamless titlebar-to-header blur only while a sticky header is active, without moving the tab bar, and aligned the top current-thread strip to the content area.
- Reduced the sidebar's minimum width so it takes less space on small screens.
- Ordered stale, stopped-session, favorite, and pinned thread indicators consistently, with a clearer red stopped-session icon.
- Moved thread signs inline before descriptions for a cleaner, more compact sidebar presentation, with signs dimming together with inactive thread text and a matching status icon identifying threads whose tmux sessions are stopped.
- Tightened spacing between sidebar threads while preserving stronger pinned, hidden, and section boundaries.
- Keep last-known PR/MR, Jira, hidden-thread, and stopped-session sidebar state visible immediately after relaunch while fresh checks run.
- Mark the priority matching a thread's Jira ticket in sidebar priority menus.
- Simplified section headers to plain rows and moved their color cue to diagonal top-right bands on thread capsules.
- Matched main-worktree capsules to the neutral thread background and kept a title-sized, optically aligned home icon inline when other thread icons are hidden.
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

- Fixed the sidebar sometimes failing to center the selected thread after launch.
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
- Fixed recurring crashes after archiving or deleting threads while background terminal checks or tmux recovery were running.
- Prevented newly created thread selection from being undone by stale sidebar scroll restores.
- Fixed collapsed sidebar sections corrupting row geometry after reloads, which could leave huge gaps or overlap project and section headers.
- Fixed sidebar rows and headers overlapping during new-thread creation.
- Fixed sticky section headers not blurring the sidebar content underneath.
- Fixed sticky repository headers disappearing in the gap before the next repository header takes over.
- Kept the add-thread `+` button visible on sticky repository headers.
- Fixed the add-thread `+` button on sticky repository headers not responding to clicks.
- Fixed sidebar thread clicks getting ignored after interrupted drag interactions.
- Fixed the sidebar add-repository menu so create and import actions open reliably.
