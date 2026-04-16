# What's New Popup

Modal sheet shown once per shipped highlight feature. Defined in
`Magent/Services/WhatsNewContent.swift` (single `current` entry), orchestrated
by `WhatsNewService`, rendered by `WhatsNewSheetController`.

## Adding a new entry

1. Pick the version: usually `next-minor(currentBundleVersion)`. Older entries
   are deleted (we never re-show retroactively); a newer entry overrides any
   prior one regardless of whether the user saw it.
2. Drop the screenshot into `Magent/Resources/Assets.xcassets/<Name>.imageset/`
   with a `Contents.json` marking it `@2x` (see existing
   `WhatsNewMultiWindows.imageset` for shape).
3. Replace `WhatsNewContent.current` with the new `WhatsNewEntry`. One page is
   the norm; multi-page is supported (pager dots auto-shown when `pages > 1`).
4. Run `mise x -- tuist generate --no-open` only if you added/removed source
   files (asset catalog changes don't need it).

## Image sizing convention (do this BEFORE adding to assets)

The sheet is 560 pt wide. NSImageView publishes `image.size` as its intrinsic
content size, so a giant raw screenshot will fight the sheet's width
constraints (and bloat the app bundle). Constrain the source itself:

- **Max 1400 px wide** (≈ 2x of the sheet's content area, with headroom).
- Keep **aspect ratio** of the original screenshot.
- Marked `@2x` in `Contents.json` so it renders at half its pixel size in pts.

Resize with `sips` before adding:

```bash
sips --resampleWidth 1400 path/to/source.png --out path/to/dest.png
```

Sheet-side layout already caps height at 340 pt and width at the stack width —
those are a safety net, not a substitute for sizing the asset correctly.

## Show-once gating

`WhatsNewService.showIfNeededOnLaunch` shows the entry iff
`SemanticVersion(lastSeenWhatsNewVersion) < entry.semanticVersion`. Dismissal
(via "Got it" or implicit close) persists `entry.version` to
`AppSettings.lastSeenWhatsNewVersion`. The `mAgent → What's New…` menu item
calls `showCurrent` which bypasses the gate; dismissal still records the
version (idempotent).

The menu item is enabled when `WhatsNewContent.current != nil` regardless of
the running app version — older binaries simply don't have newer entries
compiled in, so there's no cross-version leak.
