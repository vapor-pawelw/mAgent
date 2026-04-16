import Foundation

/// One page inside a What's New popup. Typically a screenshot + a short
/// feature title + description.
public struct WhatsNewPage: Sendable, Equatable {
    /// Short feature title shown above the description (e.g. "Pop-out Windows").
    public let title: String

    /// Body copy describing the feature. Plain text; newlines are preserved.
    public let body: String

    /// Name of an image set inside `Assets.xcassets`. `nil` renders a page
    /// without a screenshot.
    public let imageAssetName: String?

    public init(title: String, body: String, imageAssetName: String?) {
        self.title = title
        self.body = body
        self.imageAssetName = imageAssetName
    }
}

/// Describes the "What's New" popup that ships with a given app version.
///
/// Only a single entry exists in the codebase at any time
/// (`WhatsNewContent.current`). It is replaced each release — older
/// screenshots/copy get deleted rather than archived, since we never want to
/// show previous entries retroactively.
public struct WhatsNewEntry: Sendable, Equatable {
    /// Semantic version that this popup is associated with (e.g. "1.6.0").
    /// Users see the popup once when upgrading to — or installing — this
    /// version or any later version, provided they haven't already seen it.
    public let version: String

    /// One or more pages. With a single page, the sheet hides the pager UI
    /// (dots + prev/next) and simply shows the page plus "Got it".
    public let pages: [WhatsNewPage]

    public init(version: String, pages: [WhatsNewPage]) {
        self.version = version
        self.pages = pages
    }

    public var semanticVersion: SemanticVersion? {
        SemanticVersion(version)
    }
}
