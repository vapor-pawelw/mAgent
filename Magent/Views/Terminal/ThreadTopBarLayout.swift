import AppKit

enum ThreadToolbarCapsuleLayout {
    static let preferredThreadSummaryWidth: CGFloat = 260
    static let maximumThreadSummaryWidth: CGFloat = 1400
    static let minimumToolbarContentWidth: CGFloat = 260
    static let maximumToolbarContentWidth: CGFloat = 1600

    static func configureActionButton(_ button: NSButton) {
        button.lineBreakMode = .byTruncatingTail
        button.cell?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    static func configurePreferredThreadSummaryWidth(_ constraint: NSLayoutConstraint) {
        constraint.priority = .defaultHigh
    }
}

struct ThreadTopBarLayout {
    enum Item: Equatable {
        case addTab
        case review
        case continueIn
        case scrollLeft
        case userTabs
        case scrollRight
        case fixedTabs
        case fixedTabsSeparator
        case openPR
        case openJira
        case prJiraSeparator
        case openXcode
        case openFinder
        case exportContext
        case resyncLocalPaths
        case archiveSeparator
        case popOut
        case archive
    }

    struct TabGroups: Equatable {
        let fixed: Range<Int>
        let pinned: Range<Int>
        let unpinned: Range<Int>
    }

    struct UserToFixedSpacing: Equatable {
        let afterScrollView: CGFloat
        let afterRightArrow: CGFloat
    }

    static let minimumUserToFixedTabSpacing: CGFloat = 16

    static func items(prJiraHostedInInfoStrip: Bool) -> [Item] {
        var items: [Item] = [
            .addTab,
            .review,
            .continueIn,
            .scrollLeft,
            .userTabs,
            .scrollRight,
            .fixedTabs,
            .fixedTabsSeparator,
        ]
        if !prJiraHostedInInfoStrip {
            items.append(contentsOf: [.openPR, .openJira, .prJiraSeparator])
        }
        items.append(contentsOf: [
            .openXcode,
            .openFinder,
            .exportContext,
            .resyncLocalPaths,
            .archiveSeparator,
            .popOut,
            .archive,
        ])
        return items
    }

    static func tabGroups(tabCount: Int, fixedCount: Int, pinnedBoundary: Int) -> TabGroups {
        let count = max(0, tabCount)
        let fixedUpperBound = min(max(fixedCount, 0), count)
        let pinnedUpperBound = min(max(pinnedBoundary, 0), count)
        let pinnedStart = min(fixedUpperBound, pinnedUpperBound)
        let unpinnedStart = min(max(pinnedUpperBound, fixedUpperBound), count)
        return TabGroups(
            fixed: 0..<fixedUpperBound,
            pinned: pinnedStart..<pinnedUpperBound,
            unpinned: unpinnedStart..<count
        )
    }

    static func userToFixedSpacing(showsScrollArrows: Bool, regularSpacing: CGFloat) -> UserToFixedSpacing {
        UserToFixedSpacing(
            afterScrollView: showsScrollArrows ? regularSpacing : minimumUserToFixedTabSpacing,
            afterRightArrow: minimumUserToFixedTabSpacing
        )
    }
}
