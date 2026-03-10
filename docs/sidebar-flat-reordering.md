# Sidebar Flat Reordering

This thread restored drag-to-reorder for projects whose sidebar section grouping is disabled.

## User-Facing Behavior

- When `Group threads by sections in the sidebar` is off, users can still drag regular threads within a project to reorder them.
- Dragging still respects the pinned/unpinned split used by the flat list:
  - pinned threads can only move within the pinned block
  - unpinned threads can only move within the unpinned block
- After a drop, the moved thread adopts the hidden section of the visible thread directly above it and is stored immediately below that thread within that section.
- If the drop lands at the top of a flat pinned/unpinned block, the moved thread uses the next visible thread as the anchor and becomes the first thread in that hidden section.
- If there is no other regular thread to anchor against, the drop is effectively a no-op.

## Implementation Notes

- `ThreadListViewController.reloadData()` still builds the flat project list by concatenating visible sections in section-order, then flattening pinned threads before unpinned threads.
- `ThreadListViewController+DataSource.swift` handles flat-list drops on `SidebarProject` when `shouldUseThreadSections(for:)` is false.
- The flat drop code converts the outline child index back into:
  - a visual insertion index within the dragged thread's pin group
  - an anchor thread from the sibling directly above the insertion point when available
  - a fallback anchor from the sibling directly below when the drop is at the top of the group
- Persistence still goes through `ThreadManager.moveThread(...toSection:)` plus `reorderThread(...inSection:)`; no separate flat-order storage exists.

## Gotchas

- Hidden sections still matter in flat mode. Reordering only by raw flat index will desynchronize the persisted section model from what the user just arranged.
- Keep flat drag validation project-scoped. Cross-project drops are not supported in the sidebar.
- Preserve the pinned/unpinned boundary in both validation and accept-drop handling, otherwise the flat list can render an order that the underlying section-based sorter will not keep after reload.
