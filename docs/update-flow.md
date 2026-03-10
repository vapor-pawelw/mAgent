# Update Flow

User-facing behavior:
- `General` settings owns update preferences and actions: the launch-check checkbox, manual `Check for Updates Now`, and an `Update to <version>` button when a newer release has already been detected.
- Launch-time update checks run only when `AppSettings.autoCheckForUpdates` is enabled.
- When no published release exists yet in `vapor-pawelw/magent-releases`, manual checks say there are no new releases instead of surfacing a raw GitHub `404`.
- When a newer version is found, Magent shows a persistent dismissible banner with `Update Now`, `Skip this version`, and a collapsed-by-default `Show Changes` control.
- Settings mirrors the same detected version and the same read-only changelog, using a fixed-height scrollable text area when expanded.
- `Skip this version` suppresses the launch/banner prompt for that exact version only. The skipped version still appears in Settings with an update button, and a newer version shows prompts again automatically.

Implementation details:
- `UpdateService` queries the public repo's release list (`/releases?per_page=10`) instead of `/releases/latest`.
- Release notes come from the GitHub release `body` and are passed through banner/settings UI as optional details text.
- Detected update state is kept in memory by `UpdateService` and broadcast with `magentUpdateStateChanged`, which `SettingsGeneralViewController` observes to refresh its update card.
- Skipped-version persistence lives in `AppSettings.skippedUpdateVersion`.
- Installing an update still uses the detached shell-script flow: direct app replacement for normal app bundles and `brew upgrade --cask magent` for Homebrew installs, followed by app relaunch.

What changed in this thread:
- Reworked update checks so launch detection no longer auto-installs immediately.
- Added persistent in-app update banners with dismiss/skip/update actions and expandable release notes.
- Added Settings-side version status, update action, and expandable scrollable changelog display.
- Added skipped-version persistence and empty-release handling for the new public release-only repository.

Gotchas for future agents:
- Do not switch back to GitHub's `/releases/latest` endpoint unless you also handle its `404`-when-empty behavior. An empty public release repo is a valid state during setup.
- `skippedUpdateVersion` suppresses the banner for that version, not the underlying detected update state. Settings should continue to show the available version so the user can install it manually.
- If you change update UI state, keep the banner flow and `SettingsGeneralViewController` in sync through `UpdateService.pendingUpdateSummary` and `magentUpdateStateChanged` rather than duplicating fetch logic in the view.
