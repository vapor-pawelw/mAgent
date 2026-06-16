# Changelog Workflow

Release notes are split by lifecycle:

- `docs/changelog/unreleased.md` contains pending release notes only. It exists only when there are unreleased user-visible changes.
- `CHANGELOG.md` contains only the latest released app version. This is bundled into the app and shown by the in-app changelog / What's New surfaces.
- `docs/changelog/archive/<version>.md` contains one previous released version per file.

## During normal work

For every user-visible change, add a short bullet under `## Unreleased` in `docs/changelog/unreleased.md`.

If `docs/changelog/unreleased.md` does not exist yet, create it with:

```markdown
## Unreleased
```

Before any agent-driven commit, run a changelog check on the pending diff and include any needed `docs/changelog/unreleased.md` updates in that same commit.

Guidelines:

- Group notes by product domain using `### <Domain>` headings (for example: `Thread`, `Sidebar`, `Settings`, `Agents`).
- Hide empty domains; only include a domain heading when it has at least one note.
- **Each `### <Domain>` heading must appear at most once in `docs/changelog/unreleased.md`.** When adding a new bullet to a domain that already exists, merge it into the existing `### <Domain>` block under the appropriate `#### Features`, `#### Improvements`, or `#### Bug Fixes` subsection instead of creating a second domain block later in the file. Before any commit that touches `docs/changelog/unreleased.md`, scan it for duplicate domain headings and collapse them.
- Order domain sections by release importance, not by when a thread happened to add its changelog entry. Put broad user-facing changes and headline fixes first; keep niche domains, CLI/API details, and supporting fixes later unless they are the primary release story.
- Keep `Thread` as a single top-level domain by default. Do not split it into permanent domains like `Thread: Rename`.
- Within each domain, use `#### Features`, `#### Improvements`, and `#### Bug Fixes` subsections as needed, in that order. Do not interleave bullets.
- Use `Features` for new user capabilities or workflows, `Improvements` for polish/usability/clarity/performance refinements to existing behavior, and `Bug Fixes` for broken, misleading, unreliable, or regressed behavior.
- If one topic inside a domain dominates a release, use an optional temporary `##### <Topic>` subheading inside `#### Features`, `#### Improvements`, or `#### Bug Fixes` and remove it in later releases when no longer needed.
- Focus on behavior users can notice: new features, fixes, UX changes, and performance improvements.
- Skip internal-only refactors unless they affect user outcomes.
- Keep bullets short and specific.
- Within each subsection, order bullets by user impact.
- **Prune superseded entries within the same unreleased cycle**: if a change is introduced and then fully reverted before any release, remove the original entry rather than adding a "removed" or "reverted" note. If a change introduces a regression that is fixed before any release, update or remove the original bullet rather than adding a separate "fix" entry.

Do not add unreleased notes to root `CHANGELOG.md`. Root `CHANGELOG.md` is release output, not the pending-notes file.

## During release

Run:

```bash
./scripts/release-interactive.sh
```

The script will:

1. Read notes from `docs/changelog/unreleased.md` under `## Unreleased`
2. Show the pending domain order so it can be reviewed before release
3. Archive the previous root `CHANGELOG.md` into `docs/changelog/archive/<old-version>.md`
4. Move the unreleased notes into root `CHANGELOG.md` as `## <version> - <YYYY-MM-DD>`
5. Remove `docs/changelog/unreleased.md`
6. Commit and push the changelog/archive update
7. Create an annotated tag containing the new root `CHANGELOG.md` version section
8. Push the tag and verify release/homebrew automation

If `docs/changelog/unreleased.md` has already been promoted and a retry is needed, rerun `./scripts/release-interactive.sh` with the same version. The helper reuses the matching version section from root `CHANGELOG.md` for the annotated tag.

GitHub Releases read release notes from root `CHANGELOG.md` for the latest release. The backfill helper searches both root `CHANGELOG.md` and `docs/changelog/archive/*.md`.

## In-app display

- The app bundles root `CHANGELOG.md` at build time and uses it for both:
  - `mAgent > Changelog…`
  - launch-time `What's New` popup
- Root `CHANGELOG.md` intentionally contains only the latest released version, so in-app changelog surfaces show only that version.
- Launch-time `What's New` is shown once per app version, tracked in `AppSettings.lastShownChangelogVersion`.
- If no matching `## <version> - ...` section exists in bundled `CHANGELOG.md`, launch skips the popup.
- Debug Settings includes a `What's New` helper to reopen the current-version popup for testing.
- Rendering (`ChangelogWindowController.attributedReleaseNotes`) groups bullets under each `### <Domain>` heading, draws a brand-tinted horizontal separator directly under the domain heading, and styles subsection labels in uppercase with the app's primary brand color. Duplicate `### <Domain>` headings within the same release are auto-merged at render time (`mergeDuplicateDomains`) as a safety net, but `docs/changelog/unreleased.md` should still be kept clean per the rules above.
- Inline markdown bold is supported in release-note body and bullet text: wrap text as `**bold**` to render bold text.
