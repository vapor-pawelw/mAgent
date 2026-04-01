# Open Action Icons

## User Behavior

- The top-right thread toolbar buttons and their matching right-click menu actions now use the same visual icon source for `Open in Finder` and pull-request / open-PR actions.
- `Open in Finder` in thread context menus uses the real Finder app icon instead of a generic folder symbol.
- Pull-request actions in thread context menus use the same hosting-provider icon as the top-right PR button when Magent knows the remote provider; otherwise they fall back to the existing generic external-link symbol.
- When Magent can detect an existing PR/MR for the current branch, toolbar and menu actions open the direct PR/MR web page instead of a host-specific filtered listing page.
- For non-main threads, PR/MR actions stay hidden until Magent gets a definitive branch lookup result from the provider CLI. A missing/failed lookup should not leave a dead "Show PR" affordance on screen.
- When the provider CLI confirms that the branch has no PR/MR yet, the non-main thread toolbar button and context menu switch to a create action instead of linking to a filtered listing page. The creation URL should prefill source branch and target/base branch whenever the hosting provider supports it, and should also prefill the PR/MR title from the thread description when available.
- The `CHANGES` panel file context menu now uses the Finder app icon for `Show in Finder` so Finder-related actions look consistent everywhere in the app.
- PR/MR metadata is populated during startup restore and refreshed on the session monitor, so sidebar labels and open actions should not wait for a long idle period after launch.

## Implementation Notes

- Shared icon generation lives in `Magent/Utilities/OpenActionIcons.swift`.
- Finder actions use `NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")` so menus and toolbar buttons stay aligned with the system Finder icon.
- Pull-request actions resolve their icon from `GitHostingProvider` and reuse the same provider artwork for both toolbar buttons and menus.
- Direct PR/MR opening should prefer `ThreadManager.resolvePullRequestActionTarget(for:)` or `GitService.lookupPullRequest(...)` before falling back to provider listing URLs. This keeps GitLab actions on the actual MR page when `glab` can resolve the branch.
- Keep PR/MR lookup state richer than `pullRequestInfo == nil`: UI needs to distinguish "no PR exists" from "lookup unavailable" so it can either show a create action or hide the affordance entirely.
- GitHub's provider mark still gets a light rounded badge so it remains readable in dark appearances.

## Gotchas

- The app target uses an explicit source allowlist in `Project.swift`, not a blanket `Magent/Utilities/**` glob. Adding a new utility file requires adding it to the `sources` array or the app target will compile without seeing it.
- When adding new "open" actions that mirror an existing toolbar button, route them through `OpenActionIcons` instead of duplicating one-off `NSWorkspace` / `NSImage(named:)` code. That keeps menus and buttons visually in sync and avoids provider-specific styling drift.
- Do not assume periodic PR/MR refresh alone will populate `pullRequestInfo` quickly enough for launch-time UI. Keep startup restore triggering a PR/MR sync, and keep direct-open actions able to resolve the live PR/MR URL on demand.
- GitLab MR lookup via `glab mr list` should treat "open" as the default list mode. Do not add a `--state opened` flag here — some `glab` builds reject it and will flip the global sync status into a false failure state.
