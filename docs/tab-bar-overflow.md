# Tab Bar Overflow

How the thread tab strip handles overflow when there are more tabs than horizontal space.

## User-facing behavior

- The tab strip is wrapped in a horizontal scroll view. When tabs overflow the available width, the strip scrolls instead of compressing tabs.
- Two chevron arrow buttons (`tabScrollLeftButton`, `tabScrollRightButton`) flank the scroll region. They are hidden entirely when there is no overflow; when shown, the arrow at whichever edge has been reached is dimmed via `isEnabled = false`.
- Clicking an arrow scrolls by one tab width (with an 80pt minimum) using a 0.2s animated `setBoundsOrigin` on the clip view.
- The native scroll bar is never shown — overflow is communicated only via the arrow buttons. `hasHorizontalScroller = false` enforces this.
- Three input methods scroll the strip: the arrow buttons, mouse-wheel input over the strip (translated from vertical to horizontal so traditional mice work), and trackpad horizontal swipes (which carry horizontal delta natively and pass through unchanged).
- Drag-to-reorder inside the tab strip behaves exactly as before — drag a tab, swap with neighbors, persist on release.

## Implementation notes

- `Magent/Views/Terminal/TabBarScrollView.swift` is the scroll-view subclass: chrome-less (no border, no background, hidden scroller), horizontal-only elasticity, and overrides `scrollWheel(with:)` to axis-swap purely vertical scroll events into horizontal panning. Trackpad events that already carry `scrollingDeltaX` pass through unchanged so their natural pan still works.
- `ThreadDetailViewController+TabBar.configureTabBarScrollView()` wraps `tabBarStack` inside a document container view and pins the document's height to the scroll view's clip view height. This forces the scroll view to scroll only on the X axis even though the stack's intrinsic height could otherwise drive vertical content size.
- `tabBarScrollView` sits inside the `topBar` `NSStackView` with low horizontal hugging (`.defaultLow - 1`) and low compression resistance, so it absorbs all leftover horizontal space before any sibling button compresses.
- Arrow visibility is recomputed by `refreshTabScrollArrowsVisibility()`. It compares `documentContainer.bounds.width` against `contentView.bounds.width` and uses `isHidden` (with `NSStackView.detachesHiddenViews = true`) to fully collapse the buttons out of the layout when there is no overflow. When visible, `isEnabled` is updated based on the current `clipView.bounds.origin.x` vs `0` and `documentWidth - clipWidth`.
- The refresh runs from four entry points: `rebuildTabBar()` (deferred via `DispatchQueue.main.async` so the new layout settles first), `viewDidLayout()`, and `NSView.boundsDidChangeNotification` / `frameDidChangeNotification` observers on `tabBarScrollView.contentView`. Both notifications require the clip view to opt-in via `postsBoundsChangedNotifications = true` and `postsFrameChangedNotifications = true`, set during `configureTabBarScrollView()`.

## Gotchas

- Do not add a trailing flex spacer back into `tabBarStack`. The previous layout used one to keep tabs left-aligned inside an unbounded stack, but the scroll view now provides that left-alignment naturally. Adding a spacer would inflate the document's intrinsic width and force the scroll view to think it is permanently in overflow.
- When measuring overflow inside `refreshTabScrollArrowsVisibility()`, use the `documentContainer` width and clip view width — not the stack's intrinsic content size. `NSStackView.fittingSize` may report a stale value when called between subview rearrangements.
- `rebuildTabBar()` runs synchronously while the stack's arranged subviews change, so the visibility refresh must be deferred (`DispatchQueue.main.async`) until after the next layout pass. Calling it inline gives wrong widths.
- `scrollWheel` axis-swap (`NSEvent.withHorizontalDelta`) needs `cgEvent?.copy()` — using the original `cgEvent` mutates the in-flight event and breaks downstream listeners. Always copy first.
- The scroll view does not consume scroll events outside its own bounds, so wheel events over the terminal area still reach Ghostty unchanged. Do not move the scroll-wheel translation into a global event monitor.

## Relevant files

- `Magent/Views/Terminal/TabBarScrollView.swift`
- `Magent/Views/Terminal/ThreadDetailViewController+TabBar.swift`
- `Magent/Views/Terminal/ThreadDetailViewController.swift` (button declarations, `setupUI` wiring, `viewDidLayout` hook)
