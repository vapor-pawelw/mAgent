# Sidebar Row Stability

## User-Facing Behavior

- Selecting a thread should not change the sidebar width.
- Selecting a thread should not make a multiline thread row grow or shrink.
- Task descriptions should keep the same wrapping/height while selection state changes.

## Implementation Notes

- Keep the main split view structure stable: swap detail content inside a persistent container instead of removing and re-adding split-view items.
- Preserve the sidebar width during detail-content swaps with `SplitViewController.preserveSidebarWidthDuringContentChange(...)`.
- Pin multiline thread text to a pre-measured width in `ThreadCell` so auto layout does not renegotiate description wrapping on selection.
- Measure multiline description height in `ThreadListViewController+DataSource` with a stable font that does not depend on thread state that selection can clear.

## Changed In This Thread

- `heightOfRowByItem` still uses runtime description measurement for multiline rows, but the measurement font is now fixed to the widest sidebar description font.
- This avoids the regression where selecting a row cleared `hasUnreadAgentCompletion`, switched the measurement font from semibold to regular, and made the same row collapse shorter.

## Gotchas

- Do not key sidebar row-height math off `hasUnreadAgentCompletion` or other selection-sensitive flags unless the visible layout is guaranteed to stay identical before and after selection.
- A split-view width fix alone is not sufficient here. The sidebar can look like it is resizing when the real bug is row-height or text-wrap remeasurement inside the selected cell.
