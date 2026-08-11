## Unreleased

### Thread

#### Bug Fixes

- Table of Contents history now survives terminal scrollback eviction, and prompt durations are refined from agent transcripts when available.

### Agents

#### Improvements

- Agent tabs that return to an idle shell now offer a one-click **Start Agent** action without interrupting other running commands.
- Agent terminal sessions now start without user shell plugins, themes, aliases, or update checks, while standard terminal tabs continue using the user's normal shell setup.
- Magent can now detect, skip, and install Codex CLI updates without Codex interrupting new terminal sessions with its own updater.

#### Bug Fixes

- Thread and tab busy indicators now remain visible when Codex keeps its composer open below an active Working status.
- Agent completion and input-needed alerts now play their configured sound once instead of sometimes playing it twice when system banners are enabled.

### Chat

#### Improvements

- Codex chat tabs now show the selected model and reasoning effort in their names, use a clear Chat suffix, and support automatic naming from the first prompt; unfinished Claude chat entry points are hidden for now.
- Matched the chat composer’s prompt surface to the rounded input used when creating threads and tabs.
- Made assistant replies easier to read with a wider unboxed layout while keeping user prompts and important statuses visually distinct.
- Replaced the animated working bubble with a quieter inline progress row.
- Moved per-message timestamps and model metadata into hover details to make conversations denser and easier to scan.
- Unified the message composer into a cleaner rounded input surface with an integrated attachment, model, reasoning, and send footer.
- Show patch edits in chat as clean changed-file links that open the focused diff instead of rendering raw patch/output text.
- Compacted consecutive chat activity rows into a collapsed expandable summary with clear system icons so restored agent work is easier to scan.
- Made chat tool activity cleaner by showing concise action summaries and keeping successful tool output collapsed by default.
- Hid internal command transport settings and kept command results from replacing useful action summaries with arbitrary output text.
- Show chat cancellations, errors, and approval-blocked Codex turns as clearer status bubbles.

#### Bug Fixes

- Prevented overlapping GUI/CLI turns from corrupting one chat, honored the selected terminal/chat destination in `Continue in...`, preserved pinning and active selection when closing or restoring chat tabs, and kept legacy model pickers aligned with the model used for requests.
- Kept Codex chat permissions in sync with Agent Settings when continuing an existing conversation, including Full Access and sandbox mode.
- Prevented failed or approval-blocked Codex turns from replaying the same prompt, preserved steering messages that race with completion, and stopped queued prompts from starting after closing or clearing a chat.
- Preserved model-change markers, local chat statuses, repeated-message identity, timestamps, attachments, and model metadata when restoring Codex transcripts.
- Reused warmed Codex chat processes between prompts so later replies no longer wait for integrations to initialize again.
- Fixed Codex’s no-reasoning option being labeled `Fast` in chat controls.
- Fixed Codex chat tabs crashing when restored activity summaries contained multiple icon rows.
- Kept `/help` reasoning choices aligned with every effort level supported by the selected Codex model.
- Keep failed or still-running tools and action-required chat statuses visible instead of hiding them inside collapsed activity summaries.
- Fixed `Continue in...` from a Codex chat showing only Claude Code instead of including and preferring the configured Codex default.

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
