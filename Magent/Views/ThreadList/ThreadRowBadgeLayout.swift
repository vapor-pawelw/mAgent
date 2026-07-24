import AppKit

enum ThreadRowBadgeLayout {
    enum MainWorktreeIconPlacement: Equatable {
        case leading
        case inlineAfterTitle
    }

    static let compactTextFontSize: CGFloat = 9
    enum TrailingMarkerVerticalAnchor: Equatable {
        case textRows
    }

    static let topContentPadding: CGFloat = 8
    static let titleToSubtitleSpacing: CGFloat = 3
    static let textToStatusRowSpacing: CGFloat = 8
    static let bottomContentPadding: CGFloat = 8
    static let statusRowHeight: CGFloat = 13
    static let standardStatusIconSize: CGFloat = 13
    static let compactLeadingStatusIconSize: CGFloat = 11
    static let trailingMarkerVerticalAnchor: TrailingMarkerVerticalAnchor = .textRows

    static func inlineMainWorktreeIconSize(titleFont: NSFont) -> CGFloat {
        titleFont.pointSize
    }

    static func mainWorktreeIconPlacement(showThreadIcons: Bool) -> MainWorktreeIconPlacement {
        showThreadIcons ? .leading : .inlineAfterTitle
    }

    static func primaryText(_ text: String, signEmoji: String?) -> String {
        guard let signEmoji, !signEmoji.isEmpty else { return text }
        return "\(signEmoji) \(text)"
    }

    static func subtitleText(
        hasDescription: Bool,
        branchName: String,
        worktreeName: String,
        showWorktreeName: Bool,
        isMainWorktree: Bool = false
    ) -> String? {
        if isMainWorktree {
            return branchName.isEmpty ? nil : branchName
        }
        let hasDistinctWorktreeName = worktreeName != branchName
        if hasDescription {
            return showWorktreeName && hasDistinctWorktreeName
                ? "\(branchName)  ·  \(worktreeName)"
                : branchName
        }
        return showWorktreeName && hasDistinctWorktreeName ? worktreeName : nil
    }

    static func highlightedTicketRange(in branchName: String, ticketKey: String?) -> Range<String.Index>? {
        guard let ticketKey, !ticketKey.isEmpty else { return nil }
        return branchName.range(of: ticketKey, options: [.caseInsensitive])
    }

    static func highlightedTicketText(
        _ text: String,
        ticketKey: String?,
        font: NSFont,
        baseColor: NSColor,
        highlightColor: NSColor,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString? {
        guard let range = highlightedTicketRange(in: text, ticketKey: ticketKey) else {
            return nil
        }
        let attributedText = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: baseColor,
                .paragraphStyle: paragraphStyle,
            ]
        )
        attributedText.addAttribute(
            .foregroundColor,
            value: highlightColor,
            range: NSRange(range, in: text)
        )
        return attributedText
    }

    static func pullRequestBadgeText(number: String, status: String) -> String {
        "\(number) \(status)"
    }

    enum ActivityBadgeLabel: Equatable {
        case stale
        case busy
    }

    enum ActivityBadgeTone: Equatable {
        case yellow
        case orange
        case red
    }

    struct ActivityBadge: Equatable {
        let label: ActivityBadgeLabel
        let tone: ActivityBadgeTone
    }

    struct StoppedSessionsBadge: Equatable {
        let symbolName: String
        let tone: ActivityBadgeTone
    }

    static let stoppedSessionsBadge = StoppedSessionsBadge(
        symbolName: "xmark.circle",
        tone: .red
    )

    static func activityBadge(
        forElapsed elapsed: Int,
        isBusy: Bool,
        isMainWorktree: Bool = false
    ) -> ActivityBadge? {
        if isMainWorktree && !isBusy {
            return nil
        }

        return if isBusy {
            switch elapsed {
            case ..<3_600: nil
            case ..<18_000: ActivityBadge(label: .busy, tone: .yellow)
            case ..<86_400: ActivityBadge(label: .busy, tone: .orange)
            default: ActivityBadge(label: .busy, tone: .red)
            }
        } else {
            switch elapsed {
            case ..<604_800: nil
            case ..<1_209_600: ActivityBadge(label: .stale, tone: .yellow)
            case ..<2_592_000: ActivityBadge(label: .stale, tone: .orange)
            default: ActivityBadge(label: .stale, tone: .red)
            }
        }
    }

    enum ActivityBadgeMenuAction: Equatable {
        case toggleHidden
        case archive
    }

    static func activityBadgeMenuActions(
        isBusy: Bool,
        isMainWorktree: Bool
    ) -> [ActivityBadgeMenuAction] {
        guard !isBusy, !isMainWorktree else { return [] }
        return [.toggleHidden, .archive]
    }

    static func priorityOptionLabel(
        _ label: String,
        level: Int,
        jiraPriority: Int?,
        jiraAnnotation: String
    ) -> String {
        guard level == jiraPriority else { return label }
        return "\(label) \(jiraAnnotation)"
    }

    enum LeadingStatusItem: CaseIterable {
        case priority
        case jiraStatus
        case pullRequestStatus
    }

    enum TrailingStatusItem: CaseIterable {
        case rateLimit
        case jiraSync
        case keepAlive
        case hidden
        case activityDuration
        case stoppedSessions
        case favorite
        case pinned
    }

    static func showsKeepAliveBadge(isKeepAlive: Bool) -> Bool {
        isKeepAlive
    }
}
