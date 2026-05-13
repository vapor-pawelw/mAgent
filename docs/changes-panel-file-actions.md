# Changes Panel File Actions

## User Behavior

- In the sidebar `CHANGES` panel, single-clicking a file still selects it and opens the inline diff viewer for that path.
- Added directories in the `CHANGES` panel now render with a folder icon, a trailing slash in the label, and a full-path tooltip on hover so they are easier to distinguish from files.
- The `CHANGES` panel `ⓘ` legend popover keeps consistent padding around every row instead of letting the first rows sit flush against the popover edge.
- Inline diff rendering is handled by the bundled web renderer in a local `WKWebView`, so text selection and copy behavior are provided by WebKit.
- Double-clicking a file opens the file with the system default macOS app.
- Right-clicking a file opens a context menu with `Copy Filename`, `Show in Finder`, and (for non-committed files) `Stage`, `Unstage`, or `Discard Changes`. Directory rows also show the stage/unstage/discard options when applicable. The `DiffFileRowView.workingStatus` property is set from `FileDiffEntry.workingStatus` in `makeEntryRow`; stage/unstage calls `GitService.shared.stageFile`/`unstageFile` then fires `onRefreshRequested` to reload the panel. Discard prompts a warning alert first, then uses `GitService.shared.discardFile(...)` to reset tracked paths or remove untracked paths. On success, the file is removed from the list immediately via `optimisticallyRemoveFile(path:)` before the async git refresh runs — so the row disappears without waiting for the next refresh cycle. The async refresh still follows to confirm final state, and if a manual refresh is already running the discard queues one follow-up pass so the panel does not stay stale.
- Right-clicking the `Uncommitted` row in the `COMMITS` tab now opens a context menu with `Discard Changes`. It uses a destructive confirmation alert and then discards all current `uncommittedEntries` paths in that worktree (tracked + untracked), mirroring file-level discard semantics.

## Implementation Notes

- File rows display the filename first (in status color, 11pt) followed by the directory path (gray, 10pt, smaller). Directory path is truncated from the leading side with `…` if the total exceeds 50 characters, prioritizing filename visibility. Truncation mode is `byTruncatingTail` so the filename is always visible.
- Row interactions are implemented in `Magent/Views/ThreadList/DiffPanelView.swift` (`DiffFileRowView` + `DiffPanelView` callbacks).
- The panel needs the selected thread's `worktreePath` to resolve `FileDiffEntry.relativePath` into a real file URL; this is passed from `ThreadListViewController+SidebarActions.refreshDiffPanel(for:)`.
- File entries from `parseDiffEntries` are sorted by `FileWorkingStatus.sortOrder` (untracked 0 → unstaged 1 → staged 2 → committed 3), then alphabetically by `relativePath` within each group. This applies to all views: commit detail, uncommitted, and ALL CHANGES.
- `GitService` diff/status commands force `core.quotePath=false` so sidebar entries use stable, unquoted relative paths even when filenames contain spaces or other characters Git would C-escape by default.
- Opening files uses `NSWorkspace.shared.open(url)`.
- Revealing files in Finder uses `NSWorkspace.shared.activateFileViewerSelecting([url])`.
- Missing files (for example deleted paths still listed in diff stats) show a warning banner instead of failing silently.
- Discard is only available for rows whose `workingStatus` is not `.committed`. Tracked staged/unstaged rows are reset to `HEAD` with `git restore --staged --worktree`; untracked rows are removed with `git clean -fd`. Committed rows intentionally have no discard action.
- Bulk uncommitted-row discard uses the same underlying per-path `GitService.discardFile(...)` path (tracked paths as restore, untracked paths as clean), then triggers one panel refresh. If any path fails, show a warning banner with the failure count and still refresh so UI state converges to git state.
- Directory detection is UI-side in `DiffPanelView`: treat a path as a directory when it ends in `/` or resolves to a directory under the selected worktree path. Untracked directory rows can otherwise look identical to files because Git status reports them as plain paths.
- The inline viewer is a local WebKit host for `Magent/Resources/DiffRenderer/dist`. Keep git/status/file-list behavior in Swift and pass unified patch text into the renderer. Core diff rendering must stay bundled and work offline; syntax-highlighting language modules may be lazily imported from a CDN after the diff is visible, and should fail back to plain text if the network is unavailable.
- `InlineDiffViewController` keeps the `WKWebView` transparent behind an AppKit loading overlay until the renderer posts `rendered`. This prevents WebKit's initial blank page from flashing white and keeps the loading state aligned with the app theme.
- The renderer source lives beside the built bundle in `Magent/Resources/DiffRenderer/src`. After changing it, run `npm install` if dependencies changed, then `npm run build`, and commit the updated `dist` assets. `node_modules` must remain untracked.
- The legend popover in `DiffPanelView.makeLegendViewController()` should use explicit container-to-stack inset constraints for padding. Relying on `NSStackView.edgeInsets` alone can render inconsistently in AppKit popovers.

## Scroll-sync: CHANGES tab follows diff viewer

When the inline diff viewer is open, the CHANGES tab selection tracks the top visible file reported by the WebKit renderer. Clicking a file in the sidebar scrolls the renderer to that file.

**Implementation**: `InlineDiffViewController.scrollToFile(_:)` forwards the normalized path into `window.magentDiffRenderer.scrollToFile(...)`, which finds the corresponding rendered file section by parsed patch metadata. The renderer posts `scrolledToFile` messages for the top visible section, and Swift re-posts the existing `magentDiffViewerScrolledToFile` notification so `DiffPanelView` does not need to know whether the viewer is native AppKit or WebKit.

**Gotcha**: Use the selector-based `addObserver(_:selector:name:object:)` form rather than the closure-based `addObserver(forName:object:queue:using:)` form. The closure form stores a non-Sendable `NSObjectProtocol` token that cannot be accessed from a nonisolated `deinit`, and the closure itself requires `MainActor.assumeIsolated` to call `@MainActor`-isolated methods. The selector form sidesteps both issues.

## Gotcha

- Right-click selection must not call the same path as left-click selection. Left-click posts `magentShowDiffViewer`, while right-click should only update row highlight and show the menu. This avoids unexpectedly opening/changing the inline diff while using context actions.
- Directory rows must not post `magentShowDiffViewer`. Main-thread working-tree status can surface newly added directories that have no meaningful unified diff target, so the row should stay Finder-oriented instead of pretending it is a file diff anchor.
- Rename paths from `git diff --numstat` can use brace syntax (for example `src/{old => new}.swift`) that does not match patch headers (`src/new.swift`). Normalize to the new/current path before wiring `FileDiffEntry.relativePath` into viewer scroll/expand lookups.
- `InlineDiffViewController` intentionally remains the stable Swift boundary. Keep callers using `setDiffContent`, `setDiffUnavailableMessage`, `expandFile`, `expandAll`, `collapseAll`, and `scrollToFile`; WebKit details should stay hidden inside that controller.
- `WKWebViewConfiguration.websiteDataStore` should stay non-persistent for the diff renderer. The renderer loads local files and receives patch text from Swift; it should not retain browsing state.
- The local renderer uses module scripts from `file://` URLs. Keep `allowFileAccessFromFileURLs` and `allowUniversalAccessFromFileURLs` enabled on the diff `WKWebViewConfiguration`; without them, WebKit finishes the HTML load but never executes the bundled renderer.
- WebKit script messages should go through a weak wrapper so the user content controller does not retain the view controller. Avoid adding `self` directly as a long-lived script handler.
- Image diffs are no longer rendered by the inline AppKit viewer. If image-specific review returns, implement it as an explicit renderer feature rather than reviving parallel native section rendering inside the WebKit-backed viewer.
