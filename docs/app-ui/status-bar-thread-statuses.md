# Status Bar Thread Statuses

This doc covers the aggregate thread-status controls in the bottom status bar.

## User-facing behavior

- The left side of the bottom status bar starts with the session-count control, followed by thread-status types the user selected to expand by default. The right side keeps collapsed status types compact, with sync status remaining the rightmost item.
- Users choose default-expanded status types in Settings -> Threads -> Status Bar. Checked types expand into one-line clickable thread badges when space allows; unchecked types always stay collapsed on the trailing side.
- Status types always keep this left-to-right order: favorites, done, waiting for input, busy, popout windows, rate limited.
- Inline thread badges show the thread description when present, otherwise the thread name. Thread text is shown up to 60 characters; longer text uses the first 58 characters plus an ellipsis. When multiple projects are configured, the badge includes the project name as a small dimmed trailing label.
- Inline badges are grouped by logical status with one tinted status glyph before each group. Badges do not repeat the glyph or show status words; the shared glyph color, matching border color, and tooltip provide the context.
- If the checked inline groups do not fit cleanly, the status bar collapses the lowest-priority checked group and tries again until the remaining inline groups and trailing collapsed controls fit.
- Inline favorite badges can be dragged left or right to reorder Favorites directly from the status bar. A slim insertion marker shows the drop position.
- Right-clicking an inline favorite badge includes `Set Favorite Alias...`, which opens a text input prefilled with the saved alias or the thread's current description/name. Saving an empty value clears the alias and returns the badge to the default description/name.
- When at least one thread is favorited, a dedicated `X favorites` control appears immediately after the session-count control, using a primary-color heart icon.
- Each aggregate status is clickable. Clicking one opens a compact popover that looks like a tooltip and shows up to the 3 most recently added matching threads.
- Clicking a thread row in that popover dismisses it and navigates directly to that thread.
- The popover is ordered so the newest matching thread sits closest to the mouse cursor. Because the popover opens above the bottom status bar, that means the newest row is rendered at the bottom.
- In the `done` popover, each row shows a trailing checkmark button that marks that thread as read without navigating away. The list refreshes immediately to keep showing the newest 3 unread completed threads.
- Marking rows as read from the `done` popover keeps the popover open and refreshes its content in place, so users can clear multiple rows quickly.
- While the `done` popover is open, the status-bar `done` count updates immediately after each mark-as-read action.
- Using the `done` popover footer `Mark All as Read` action updates the status bar immediately too; if that clears all done threads, the popover closes right away.
- The `done` popover also includes a footer button, `Mark All as Read`, below the thread rows.
- Right-clicking the status-bar `done` item opens a context menu with a single action: `Mark All as Read`.
- Clicking `X favorites` opens a favorites popover (same visual style as `done`) listing all favorite threads in chronological favorite order.
- Navigating to a thread from the favorites popover now mirrors the sidebar jump-capsule behavior: if the thread row is offscreen, the sidebar scrolls smoothly to center it and applies the same brief row pulse.
- Thread icons in `favorites` and `done` popover rows use the thread's effective section color (same color source as sidebar rows when sections are enabled).
- Row selection in `favorites` and `done` popovers does not force a tab/session override. Those navigation paths preserve the destination thread's last-selected tab.
- Favorites popover rows include a trailing remove action (`heart.slash.circle`) that removes that thread from favorites without navigating.
- The favorites popover does not show `Mark All`/`Read` controls.
- When the favorites cap is reached, the favorites popover shows an inline limit hint (`10/10`).
- When any threads are open in separate windows, the trailing status stack shows a purple `X window(s)` control. Clicking it opens a popover listing those popped-out threads.
- Selecting a row in the separate-windows popover uses the same centered sidebar navigation as Favorites, so the matching row scrolls into view and pulses briefly.
- Separate-window popover rows include a trailing action that returns that thread to the main window without navigating away.
- The separate-windows popover also includes a `Close All Windows` footer action that returns every popped-out thread window to the main app.
- A session count indicator on the left side shows the number of active tmux sessions (formatted as `live/total` when some are suspended, or just `total` when all are live). Clicking it opens a popover with a breakdown of live, suspended, protected (busy/waiting/shielded/pinned), and total sessions, plus a "Close N idle sessions" button that kills all non-protected live sessions. Clicking the button shows a confirmation alert listing which threads/tabs will be affected (scrollable, grouped by thread). Tab metadata is preserved — sessions are lazily recreated when the user selects the tab.
- The sync label on the right side shows "Synced X ago" with a tooltip explaining what is synced (PR status from GitHub, plus Jira ticket info when any project has Jira sync enabled). When the latest sync fails, that same tooltip also includes the last failure reason, and right-clicking the sync label shows the last failure lines above "Refresh Now".
- The trailing rate-limit control shows active rate-limited threads in collapsed badge form. Right-clicking it offers "Lift Limit Now" and "Lift + Ignore Current Messages" per agent (Claude/Codex).
- Aggregate thread-status items and inline thread badges are clickable for navigation. Inline done/favorite badges also expose their status-specific right-click actions directly.

## Implementation details

- `StatusBarView` owns the aggregate status buttons, the per-status popover, and the ordering state used by the popover rows.
- The popover is capped at 3 rows. Selection routes through the existing `.magentNavigateToThread` notification instead of adding a second navigation path.
- Session targeting is intentionally best-effort and non-persistent for `busy`, `waiting`, `rate-limited`, and separate-window rows. `StatusBarView` resolves the first matching session from the thread's current in-memory state at click time and passes it through `.magentNavigateToThread`; if no matching session still exists, navigation falls back to thread-only selection.
- `done` and `favorites` intentionally navigate by thread only (no session hint) so they do not mutate the destination thread's last-selected tab.
- `done` ordering is persistent because unread completion state already survives relaunch via `MagentThread.unreadCompletionSessions`, and its ordering timestamp comes from persisted `MagentThread.lastAgentCompletionAt`.
- `busy`, `waiting`, and `rate-limited` ordering is in-memory only. Their "added at" timestamps are tracked inside `StatusBarView` for the current app run and reset on relaunch because those statuses themselves are transient.
- `separate windows` ordering is also in-memory only. The underlying popped-out state persists across relaunch, but the popover order is rebuilt from the current run's status-tracking timestamps.
- Favorites ordering uses persisted `MagentThread.favoritedAt` (fallback `createdAt`) and is not capped to 3 rows like status summaries. Inline drag reordering rewrites `favoritedAt` values in chronological order so existing favorite ordering consumers stay in sync.
- Favorite aliases are stored on `MagentThread.favoriteAlias`, not on the current favorite membership. Removing a thread from Favorites does not clear the alias; if the thread is favorited again later, the inline badge reuses it.
- Favorites row selection posts `.magentNavigateToThread` with `centerInSidebar = true`; `SplitViewController` consumes that hint to suppress immediate `scrollRowToVisible` and call `ThreadListViewController.centerAndPulseThreadRow(byId:)`.
- Separate-window row selection uses that same `.magentNavigateToThread` + `centerInSidebar = true` path rather than a second sidebar-navigation implementation.
- Separate-window close actions should still route through `PopoutWindowManager` so the same persistence, duplicate-window guards, and sidebar/status notifications fire as they do for context-menu or keyboard-triggered returns.
- While a status popover is visible, `StatusBarView` avoids rebuilding the status-button stack (to preserve the popover anchor) and updates existing button counts in place.
- If a read action clears the currently open status entirely (for example, `done` goes to zero after `Mark All as Read`), `StatusBarView` must close that popover and rebuild the status-button stack immediately so stale `done` UI does not linger.
- Inline badge mode is opportunistic. `StatusBarView` measures the space left after the protected session count and projected trailing status/sync controls, then drops lower-priority checked inline groups before falling back to aggregate mode.
- Inline badge group priority is favorites, done, waiting, busy, popout windows, then rate limited. A group is rendered as a full group or not at all; the status bar does not mix inline badges with `+more` overflow controls.

## Gotchas

- Preserve the mixed persistence model: only `done` ordering should survive relaunch. Do not persist `busy` / `waiting` / `rate-limited` tooltip ordering unless those underlying states also become persisted first.
- When choosing the 3 rows to show, sort by newest-added first, take the latest 3, then reverse them for display so the newest row ends up bottom-most near the status-bar anchor.
- Keep sync status rightmost. Collapsed status controls stay in the trailing status stack and keep the fixed global order.
- Favorites can be either inline or collapsed like other status types. Keep the hidden legacy favorites button only as a fallback anchor; visible favorites controls should come from the normal inline/trailing status rendering path.
- Keep sync failure details sourced from the most recent sync runner output rather than inventing independent UI-only error state, so hover text and the sync context menu stay in sync.
- For the `done` popover row-level mark-read button, suppress row navigation when the click lands inside the button hit area. Otherwise the click can both mark as read and navigate, which is surprising and can race popover refresh.
- Keep popover content rows at a fixed width. The popover width is constant; description text may wrap up to two lines, but content must never change the popover width while rows are being marked read.
