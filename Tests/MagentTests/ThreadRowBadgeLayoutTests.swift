import AppKit
import Testing

@Suite
struct ThreadRowBadgeLayoutTests {

    @Test("Activity badges only appear after the busy and idle thresholds")
    func activityBadgeThresholds() {
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 3_599, isBusy: true) == nil)
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 3_600, isBusy: true) == .init(label: .busy, tone: .yellow))
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 17_999, isBusy: true)?.tone == .yellow)
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 18_000, isBusy: true)?.tone == .orange)
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 86_400, isBusy: true)?.tone == .red)

        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 604_799, isBusy: false) == nil)
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 604_800, isBusy: false) == .init(label: .stale, tone: .yellow))
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 1_209_599, isBusy: false)?.tone == .yellow)
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 1_209_600, isBusy: false)?.tone == .orange)
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 2_591_999, isBusy: false)?.tone == .orange)
        #expect(ThreadRowBadgeLayout.activityBadge(forElapsed: 2_592_000, isBusy: false)?.tone == .red)
    }

    @Test("Main worktree never shows a stale activity badge")
    func mainWorktreeIdleBadgeIsSuppressed() {
        #expect(ThreadRowBadgeLayout.activityBadge(
            forElapsed: 2_592_000,
            isBusy: false,
            isMainWorktree: true
        ) == nil)
        #expect(ThreadRowBadgeLayout.activityBadge(
            forElapsed: 3_600,
            isBusy: true,
            isMainWorktree: true
        )?.label == .busy)
    }

    @Test("Only stale badges on regular threads offer Hide and Archive")
    func staleBadgeMenuActions() {
        #expect(ThreadRowBadgeLayout.activityBadgeMenuActions(
            isBusy: false,
            isMainWorktree: false
        ) == [.toggleHidden, .archive])
        #expect(ThreadRowBadgeLayout.activityBadgeMenuActions(
            isBusy: true,
            isMainWorktree: false
        ).isEmpty)
        #expect(ThreadRowBadgeLayout.activityBadgeMenuActions(
            isBusy: false,
            isMainWorktree: true
        ).isEmpty)
    }

    @Test("Workflow metadata leads with priority, Jira, then pull request status")
    func leadingStatusOrder() {
        #expect(ThreadRowBadgeLayout.LeadingStatusItem.allCases == [
            .priority, .jiraStatus, .pullRequestStatus,
        ])
    }

    @Test("Priority menus identify the level matching Jira")
    func priorityMenuIdentifiesJiraPriority() {
        #expect(ThreadRowBadgeLayout.priorityOptionLabel("Priority 3", level: 3, jiraPriority: 3, jiraAnnotation: "(Jira)") == "Priority 3 (Jira)")
        #expect(ThreadRowBadgeLayout.priorityOptionLabel("Priority 2", level: 2, jiraPriority: 3, jiraAnnotation: "(Jira)") == "Priority 2")
        #expect(ThreadRowBadgeLayout.priorityOptionLabel("Priority 3", level: 3, jiraPriority: nil, jiraAnnotation: "(Jira)") == "Priority 3")
    }

    @Test("Local state indicators keep stale, stopped, favorite, and pinned together at the trailing edge")
    func trailingStatusOrderPreservesStateIndicatorOrder() {
        #expect(ThreadRowBadgeLayout.TrailingStatusItem.allCases == [
            .rateLimit, .jiraSync, .keepAlive, .hidden,
            .activityDuration, .stoppedSessions, .favorite, .pinned,
        ])
    }

    @Test("Stopped sessions use the unfilled red xmark indicator")
    func stoppedSessionsBadgePresentation() {
        #expect(ThreadRowBadgeLayout.stoppedSessionsBadge == .init(
            symbolName: "xmark.circle",
            tone: .red
        ))
    }

    @Test("Explicit Keep Alive always shows its shield")
    func keepAliveBadgeVisibility() {
        #expect(ThreadRowBadgeLayout.showsKeepAliveBadge(isKeepAlive: true))
        #expect(!ThreadRowBadgeLayout.showsKeepAliveBadge(isKeepAlive: false))
    }

    @Test("Pull request badge combines the short number and status")
    func pullRequestBadgeText() {
        #expect(ThreadRowBadgeLayout.pullRequestBadgeText(number: "#392", status: "Open") == "#392 Open")
        #expect(ThreadRowBadgeLayout.pullRequestBadgeText(number: "!18", status: "Draft") == "!18 Draft")
    }

    @Test("Branch ticket highlighting finds the detected key without changing its case")
    func branchTicketHighlightRange() throws {
        let branch = "feature/ip-392-sidebar"
        let range = try #require(ThreadRowBadgeLayout.highlightedTicketRange(in: branch, ticketKey: "IP-392"))
        #expect(branch[range] == "ip-392")
        #expect(ThreadRowBadgeLayout.highlightedTicketRange(in: branch, ticketKey: "IP-999") == nil)
    }

    @Test("Branch ticket highlighting preserves typography and only colors the detected key")
    func branchTicketHighlightAttributes() throws {
        let text = "feature/ip-392-sidebar"
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        let attributedText = try #require(ThreadRowBadgeLayout.highlightedTicketText(
            text,
            ticketKey: "IP-392",
            font: font,
            baseColor: .secondaryLabelColor,
            highlightColor: .controlAccentColor,
            paragraphStyle: paragraphStyle
        ))

        #expect(attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == font)
        #expect(
            (attributedText.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
                .lineBreakMode == .byTruncatingTail
        )
        let ticketRange = try #require(text.range(of: "ip-392"))
        let ticketIndex = NSRange(ticketRange, in: text).location
        #expect(
            attributedText.attribute(.foregroundColor, at: ticketIndex, effectiveRange: nil) as? NSColor
                == NSColor.controlAccentColor
        )
        #expect(ThreadRowBadgeLayout.highlightedTicketText(
            text,
            ticketKey: "IP-999",
            font: font,
            baseColor: .secondaryLabelColor,
            highlightColor: .controlAccentColor,
            paragraphStyle: paragraphStyle
        ) == nil)
    }
}
