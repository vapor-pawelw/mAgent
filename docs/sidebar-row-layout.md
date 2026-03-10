# Sidebar Row Layout

This thread refined the left-rail and spacing rules for project headers, section rows, and the main thread row in the sidebar.

## User-Facing Behavior

- Project headers no longer show the accent bar.
- The `Main worktree` row now carries the accent bar instead.
- The `Main worktree` row uses:
  - line 1: `Main worktree`
  - line 2: current branch name when available
- Section headers and the main-thread labels share the same leading text rail.
- Threads inside sections keep their extra indentation level relative to top-level rows.
- Project separators sit closer to the following repo name, while the first repo still keeps a visible gap from the very top of the sidebar.

## Implementation Notes

- Shared rails live in `ThreadListViewController`:
  - `projectSpacerDividerLeadingInset` is the base left rail for separators.
  - `sidebarRowLeadingInset` reuses that rail for section dots, main-row accent bar, and top-level thread geometry.
  - `projectHeaderTitleLeadingInset` is the slightly inset text rail used by repo titles.
- `ThreadListViewController+DataSource.swift` uses `threadLeadingOffset(for:in:)` to cancel AppKit outline indentation for level-1 rows while preserving extra indentation for threads nested inside sections.
- `ThreadCell` owns the main-row accent bar and toggles it only for `configureAsMain(...)`.
- The main-thread leading stack uses `detachesHiddenViews = true` so hiding the row icon does not leave phantom horizontal spacing.

## Gotchas

- Do not treat AppKit outline indentation as the final visual layout. `NSOutlineView` still applies its own level offset before the cell's constraints run, so top-level rows need explicit compensation.
- Keep the main-row accent bar aligned to `sidebarRowLeadingInset - outlineIndentationPerLevel`; otherwise it drifts away from the section-dot rail.
- If you change the main-row copy again, preserve the two-line structure unless you also revisit `heightOfRowByItem`.
- Top spacing before the first repo row is driven by `scrollViewTopConstraint` / `sidebarTopInset`, not by `NSScrollView.contentInsets`.
