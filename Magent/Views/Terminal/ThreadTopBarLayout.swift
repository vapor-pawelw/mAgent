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

enum ThreadTabIdentity: Hashable {
    case permanentTerminal(sessionName: String)
    case permanentDiff
    case terminalSession(String)
    case web(String)
    case draft(String)
    case chat(String)

    static func terminal(
        sessionName: String,
        permanentTerminalSessionName: String?
    ) -> ThreadTabIdentity {
        if sessionName == permanentTerminalSessionName {
            return .permanentTerminal(sessionName: sessionName)
        }
        return .terminalSession(sessionName)
    }

    var isPermanent: Bool {
        switch self {
        case .permanentTerminal, .permanentDiff:
            true
        case .terminalSession, .web, .draft, .chat:
            false
        }
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
        let fixed: [Int]
        let pinned: [Int]
        let unpinned: [Int]
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

    static func tabGroups(
        identities: [ThreadTabIdentity],
        pinnedMovableCount: Int
    ) -> TabGroups {
        let fixed = identities.indices.filter { identities[$0].isPermanent }
        let movable = identities.indices.filter { !identities[$0].isPermanent }
        let pinnedCount = min(max(0, pinnedMovableCount), movable.count)
        return TabGroups(
            fixed: fixed,
            pinned: Array(movable.prefix(pinnedCount)),
            unpinned: Array(movable.dropFirst(pinnedCount))
        )
    }

    static func userToFixedSpacing(showsScrollArrows: Bool, regularSpacing: CGFloat) -> UserToFixedSpacing {
        UserToFixedSpacing(
            afterScrollView: showsScrollArrows ? regularSpacing : minimumUserToFixedTabSpacing,
            afterRightArrow: minimumUserToFixedTabSpacing
        )
    }
}
