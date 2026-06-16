# Releasing

Before releasing, make sure `docs/changelog/unreleased.md` has user-facing notes under `## Unreleased`.
See [docs/changelog/README.md](../changelog/README.md) for the changelog workflow.

If the release ships a notable highlight feature, also update the curated
"What's New" highlight popup (`Magent/Services/WhatsNewContent.swift`). See
[docs/app-ui/whats-new-popup.md](../app-ui/whats-new-popup.md) for the entry/image checklist.
Releases without a new highlight can leave the existing entry in place —
users who already saw it won't re-see it.

Use the interactive helper to run the full release flow:

```bash
./scripts/release-interactive.sh
```

It will:

1. Ask for the target version
2. Archive the previous root `CHANGELOG.md` into `docs/changelog/archive/<old-version>.md`
3. Promote `docs/changelog/unreleased.md` notes into root `CHANGELOG.md` as the latest version
4. Remove `docs/changelog/unreleased.md`
5. Commit and push the changelog/archive update
6. Create and push an annotated git tag with changelog notes
7. Watch the GitHub `Release` workflow until completion
8. Verify the GitHub release on `vapor-pawelw/mAgent` contains `Magent.dmg` (plus compatibility `Magent.zip`)
9. Verify `homebrew-tap/Casks/magent.rb` was updated to the same version

If your tap repo is different, set:

```bash
MAGENT_HOMEBREW_TAP_REPO=<owner>/<repo> ./scripts/release-interactive.sh
```

Manual flow (equivalent) is also tag-driven, but should use an annotated tag body:

```bash
git tag -a v1.2.0 -m "<release notes from root CHANGELOG.md>"
git push origin v1.2.0
```

This triggers a GitHub Actions workflow that:

1. Builds `Magent.app` (unsigned)
2. Publishes a GitHub Release to `vapor-pawelw/mAgent` with `Magent.dmg`, a compatibility `Magent.zip`, and release notes taken from the matching root `CHANGELOG.md` version section (`## <version> - <date>`)
3. Auto-updates the Homebrew cask formula in `vapor-pawelw/homebrew-tap` with the new version, SHA, and the public release download URL for `Magent.dmg`

The release workflow also rebuilds `Libraries/GhosttyKit.xcframework` using `./scripts/bootstrap-ghosttykit.sh` (instead of relying on git-lfs artifacts).

Commits on `main` without a tag do **not** produce a release.

Release artifacts are published directly on the source repository `vapor-pawelw/mAgent`. The workflow uses `GITHUB_TOKEN` for creating releases on the same repo, and `HOMEBREW_TAP_TOKEN` for pushing cask updates to `vapor-pawelw/homebrew-tap`.

If previously published releases have incorrect notes, you can backfill them from root `CHANGELOG.md` and `docs/changelog/archive/*.md`:

```bash
./scripts/sync-release-notes-from-changelog.sh --from-version 1.2.1
```

## Changelog Guidelines

When updating changelog notes for a release or pre-release notes:

1. Keep pending release notes in `docs/changelog/unreleased.md` under `## Unreleased`, creating that file when the first unreleased user-visible change is added. Do not put pending notes in root `CHANGELOG.md`.
2. Group notes by domain using `### <Domain>` headings (for example: `Thread`, `Sidebar`, `Settings`, `Agents`).
3. Omit empty domains; only keep headings that have at least one note.
4. Order domain sections by release importance, not by insertion time. Put broad user-facing changes and headline fixes first; keep niche CLI/API details later unless they are the main release story.
5. Keep `Thread` as a single top-level domain by default; avoid permanent split domains like `Thread: Rename`.
6. Within each domain, split entries into `#### Features` and `#### Bug Fixes` when both exist, with bug fixes listed below features.
7. If one topic dominates in a domain for a specific release, use an optional temporary `##### <Topic>` subheading inside `#### Features`/`#### Bug Fixes` and drop it once no longer needed.
8. Include only:
   - New features
   - Bug fixes
   - Performance improvements
9. Omit implementation details, internal refactors, tooling-only changes, and infrastructure-only updates.
10. Within each subsection, order entries by user impact:
   - Put broad/high-impact items first and describe them at a higher level.
   - Keep niche or smaller items shorter and place them near the end.
11. Use user-facing wording focused on outcomes, not code internals.

Root `CHANGELOG.md` contains only the latest released app version and is bundled into the app. Older released versions live one-per-file in `docs/changelog/archive/<version>.md`.

## Feature Flags

For features that should stay in the codebase but not ship yet, add a dedicated `FEATURE_*` active compilation condition in `Project.swift`, gate behavior behind that flag, hide related UI in release builds, and annotate debug-only Settings surfaces with `Debug builds only`.
