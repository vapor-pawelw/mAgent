# Hidden Threads

Hidden threads let users keep inactive work visible without archiving it.

## User-facing behavior

- Non-main thread context menus expose `Hide` / `Unhide` directly under `Pin` / `Unpin`.
- Hidden threads stay in the sidebar, but sort to the bottom of their section or flat project list.
- Hidden groups show a compact disclosure row with their thread count and start collapsed. Expanding a group is remembered independently per section or flat project.
- Navigating directly to a hidden thread automatically expands its hidden group so selection and scrolling still work.
- Hidden rows render dimmed (entire cell at 0.5 alpha) so they read as deprioritized rather than active.
- Dead-session threads use a different visual treatment: gray icon tint + `secondaryLabelColor` description text, keeping the cell at full alpha. This makes hidden vs dead states distinguishable at a glance.
- Pinning and hiding are mutually exclusive:
  - pinning a hidden thread unhides it
  - hiding a pinned thread unpins it
- CLI support mirrors the UI:
  - `magent-cli hide-thread --thread <name>`
  - `magent-cli unhide-thread --thread <name>`
- IPC thread status includes `isSidebarHidden` so external tooling can reflect the same state.

## Implementation details

- Thread persistence stores the state on `MagentThread.isSidebarHidden`.
- Sidebar ordering is modeled as three explicit groups via `ThreadSidebarListState`:
  - `pinned`
  - `visible`
  - `hidden`
- Group ordering is always `pinned`, then normal visible threads, then hidden threads.
- A blank vertical gap separates pinned and normal thread groups; it intentionally has no visible divider.
- The hidden group replaces its old passive separator with a full-width, 24-point disclosure row, with no additional gap before it. When collapsed, a standard trailing gap keeps the final disclosure row visually separate from the next section. Collapsing removes only hidden thread rows, while project and section disclosure state continues to be owned by `NSOutlineView`.
- In-section `displayOrder` remains local to a single group; reorder logic must not collapse hidden threads back into the normal unpinned group.
- New-thread placement and cross-section moves route through the same bottom-of-group helper so hidden-state behavior stays consistent after reloads and moves.

## Gotchas

- Do not treat `!isPinned` as equivalent to the normal visible group anymore. Hidden threads are also unpinned.
- Drag/drop validation must enforce all three group boundaries, not just pinned vs. unpinned.
- Main threads should never expose or accept the hidden state.
- The hidden-thread dimming is applied at the cell level (`alphaValue = 0.5`). Dead-session styling is applied per-subview (icon tint + label color) so it composes naturally when a thread is both hidden and dead.
- Selection background still comes from the row view, which keeps the selected state legible.
- Keep collapsed hidden threads in structural comparison bookkeeping, or routine metadata refreshes will look like thread removals and force repeated full sidebar reloads.

## Changes in this thread

- Added persisted hidden-thread state and three-group sidebar ordering.
- Added right-click hide/unhide actions and matching CLI commands.
- Added dimmed hidden-row rendering plus IPC/doc/changelog updates.
- Added collapsed-by-default hidden-group disclosure with persisted expansion and navigation reveal behavior.
