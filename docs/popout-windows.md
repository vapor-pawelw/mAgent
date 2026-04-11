# Pop-out Windows

This doc covers thread pop-out windows and detached terminal tabs.

## User-facing behavior

- A non-main thread can be opened in a separate window while remaining selected in the main sidebar.
- Individual terminal tabs can be detached into their own windows and later returned to the parent thread.
- Detached sessions stay protected from idle eviction and manual session cleanup while visible in a pop-out window.
- Pop-out window state is persisted across app relaunch. Reopened detached tabs should reconnect to the same live tmux session instead of showing an empty placeholder.
- Pop-out window frames are saved continuously on move/resize/screen changes, so restart restores separate thread and detached-tab windows at their latest size and position instead of their last graceful-quit frame.

## Implementation notes

- Detached terminal identity must flow through `ThreadDetailViewController.terminalReuseKey(for:sessionName:)`. Do not build ad hoc cache keys in pop-out controllers. A mismatch here causes blank detached windows or failed return-to-tab restores.
- `terminalViews` is indexed by `thread.tmuxSessionNames` order, not by `tabSlots` display order. Any detach/return/rebuild path must resolve the terminal-array index from the session name first, especially when web or draft tabs are interleaved.
- Detaching a background tab must not replace the currently visible content with a detached placeholder. Only the selected detached tab should show `DetachedTabPlaceholderView` in the main thread view.
- Cold-launch restoration cannot rely on `ReusableTerminalViewCache` alone. Detached-tab windows must be able to recreate their `TerminalSurfaceView` from the same tmux command used by the in-thread terminal view when no cached surface survives the relaunch.
- Persist pop-out state on structural changes (`pop out`, `return`, `detach`, `reattach`) and on window frame changes. Saving only during app termination is not enough if the user restarts from a crash, force-quit, or any path that bypasses orderly shutdown.

## Relevant files

- `Magent/App/PopoutWindowManager.swift`
- `Magent/App/ThreadPopoutWindowController.swift`
- `Magent/App/TabPopoutWindowController.swift`
- `Magent/Views/Terminal/ThreadDetailViewController.swift`
- `Magent/Views/Terminal/ThreadDetailViewController+Actions.swift`
- `Magent/Views/Terminal/ThreadDetailViewController+TabBar.swift`
