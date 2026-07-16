# Open Action Icons

## User Behavior

- The thread top-bar utility buttons (Finder, Xcode, etc.) and the thread info bar capsule action buttons (PR/Jira), along with their matching right-click menu actions, use the same visual icon source for `Open in Finder` and pull-request / open-PR actions.
- `Open in Finder` in thread context menus uses the real Finder app icon instead of a generic folder symbol.
- Pull-request actions in thread context menus use the same hosting-provider icon as the info-bar PR capsule when Magent knows the remote provider; otherwise they fall back to the existing generic external-link symbol.
- Right-clicking a sidebar PR/MR status badge presents the same provider-aware open action and icon, with the PR/MR number included in both the menu title and hover text. Left-clicking the badge continues to select the thread.
- When Magent can detect an existing PR/MR for the current branch, the PR capsule and menu actions open the direct PR/MR web page instead of a host-specific filtered listing page.
- For non-main threads, PR/MR actions stay hidden until Magent gets a definitive branch lookup result from the provider CLI. If a previously confirmed PR/MR exists and a later lookup becomes unavailable, keep the last confirmed action visible, dim it, and show a network-unavailable symbol until a successful lookup refreshes or clears it.
- When the provider CLI confirms that the branch has no PR/MR yet, the non-main thread PR capsule and context menu switch to a create action instead of linking to a filtered listing page. The creation URL should prefill source branch and target/base branch whenever the hosting provider supports it, and should also prefill the PR/MR title from the thread description when available.
- The `CHANGES` panel file context menu now uses the Finder app icon for `Show in Finder` so Finder-related actions look consistent everywhere in the app.
- PR/MR metadata is populated during startup restore and refreshed on the session monitor, so sidebar labels and open actions should not wait for a long idle period after launch.

## Implementation Notes

- Shared icon generation lives in `Magent/Utilities/OpenActionIcons.swift`.
- Finder actions use `NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")` so menus and toolbar buttons stay aligned with the system Finder icon.
- Pull-request actions resolve their icon from `GitHostingProvider` and reuse the same provider artwork for both toolbar buttons and menus.
- Direct PR/MR opening should prefer `ThreadManager.resolvePullRequestActionTarget(for:)` or `GitService.lookupPullRequest(...)` before falling back to provider listing URLs. This keeps GitLab actions on the actual MR page when `glab` can resolve the branch.
- Keep PR/MR lookup state richer than `pullRequestInfo == nil`: UI needs to distinguish "no PR exists" from "lookup unavailable" so it can show a create action, hide unknown actions, or preserve a stale last-confirmed PR/MR action.
- GitHub's provider mark still gets a light rounded badge so it remains readable in dark appearances.

## Gotchas

- The app target uses an explicit source allowlist in `Project.swift`, not a blanket `Magent/Utilities/**` glob. Adding a new utility file requires adding it to the `sources` array or the app target will compile without seeing it.
- When adding new "open" actions that mirror an existing toolbar button, route them through `OpenActionIcons` instead of duplicating one-off `NSWorkspace` / `NSImage(named:)` code. That keeps menus and buttons visually in sync and avoids provider-specific styling drift.
- Do not assume periodic PR/MR refresh alone will populate `pullRequestInfo` quickly enough for launch-time UI. Keep startup restore triggering a PR/MR sync, and keep direct-open actions able to resolve the live PR/MR URL on demand.
- Do not clear cached PR/MR metadata on network, CLI, auth, or remote-resolution failures. Only a confirmed `.notFound` result should clear `pullRequestInfo` and remove the branch cache entry.
- PR/MR cache keys must include project identity as well as branch name. Branch-only legacy entries may be migrated only when the branch is unique among active threads, otherwise projects with the same branch name can inherit each other's PR/MR links.
- GitLab MR lookup via `glab mr list` should treat "open" as the default list mode. Do not add a `--state opened` flag here — some `glab` builds reject it and will flip the global sync status into a false failure state.
