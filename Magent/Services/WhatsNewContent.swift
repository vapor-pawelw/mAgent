import Foundation
import MagentCore

/// The single "What's New" popup shipping with the current build.
///
/// Replace `current` whenever a new highlight feature lands — screenshot(s) in
/// `Assets.xcassets` and copy go here, and the previous entry is deleted
/// entirely (we never show older popups retroactively). Set `current = nil` to
/// ship a release with no What's New popup; the menu item stays visible but is
/// disabled.
///
/// Version bumping convention: the entry's `version` is the **next minor**
/// relative to the current `CFBundleShortVersionString` at the time of writing
/// (e.g. `1.5.4` → `1.6.0`). Users on any earlier version see it once on
/// upgrade; users who already saw an older entry see the new one exactly once.
enum WhatsNewContent {
    static let current: WhatsNewEntry? = WhatsNewEntry(
        version: "1.6.0",
        pages: [
            WhatsNewPage(
                title: "Work across multiple windows",
                body: "Pop any non-main thread out into its own window and arrange several agents side by side. Drag a sidebar row onto a pop-out to swap threads between windows — window positions and layouts are remembered across restarts.",
                imageAssetName: "WhatsNewMultiWindows"
            )
        ]
    )
}
