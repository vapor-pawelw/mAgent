import AppKit
import Testing

@Suite("Thread top bar layout")
struct ThreadTopBarLayoutTests {
    @Test("User tabs scroll before fixed tabs and trailing actions")
    func topBarOrderingAndSpacing() {
        let items = ThreadTopBarLayout.items(prJiraHostedInInfoStrip: true)

        let userTabsIndex = items.firstIndex(of: .userTabs)
        let fixedTabsIndex = items.firstIndex(of: .fixedTabs)
        let separatorIndex = items.firstIndex(of: .fixedTabsSeparator)
        let xcodeIndex = items.firstIndex(of: .openXcode)

        #expect(fixedTabsIndex == userTabsIndex.map { $0 + 2 })
        #expect(separatorIndex == fixedTabsIndex.map { $0 + 1 })
        #expect(xcodeIndex == separatorIndex.map { $0 + 1 })
        #expect(!items.contains(.openPR))
        #expect(!items.contains(.openJira))
    }

    @Test("Permanent tabs stay outside the scrollable user-tab stack")
    func fixedAndUserTabGrouping() {
        let groups = ThreadTopBarLayout.tabGroups(
            identities: [
                .permanentTerminal(sessionName: "thread-terminal"),
                .permanentDiff,
                .terminalSession("agent-1"),
                .web("docs"),
                .terminalSession("agent-2"),
                .chat("chat"),
            ],
            pinnedMovableCount: 2
        )

        #expect(groups.fixed == [0, 1])
        #expect(groups.pinned == [2, 3])
        #expect(groups.unpinned == [4, 5])
    }

    @Test("Permanent identity wins when persisted tab order is interleaved")
    func permanentIdentityDoesNotDependOnArrayPosition() {
        let groups = ThreadTopBarLayout.tabGroups(
            identities: [
                .terminalSession("agent"),
                .permanentTerminal(sessionName: "thread-terminal"),
                .web("docs"),
                .permanentDiff,
            ],
            pinnedMovableCount: 1
        )

        #expect(groups.fixed == [1, 3])
        #expect(groups.pinned == [0])
        #expect(groups.unpinned == [2])
    }

    @Test("Only the dedicated terminal session receives permanent identity")
    func permanentTerminalIdentityUsesDedicatedSessionName() {
        let dedicatedSession = "ma-magent-clefable-terminal"
        let agentSession = "ma-magent-clefable-codex--5-6-sol--m-"

        #expect(
            ThreadTabIdentity.terminal(
                sessionName: dedicatedSession,
                permanentTerminalSessionName: dedicatedSession
            ) == .permanentTerminal(sessionName: dedicatedSession)
        )
        #expect(
            ThreadTabIdentity.terminal(
                sessionName: agentSession,
                permanentTerminalSessionName: dedicatedSession
            ) == .terminalSession(agentSession)
        )
    }

    @Test("Sixteen-point separation follows the visible scroll control")
    func minimumSpacing() {
        let withoutArrows = ThreadTopBarLayout.userToFixedSpacing(
            showsScrollArrows: false,
            regularSpacing: 4
        )
        let withArrows = ThreadTopBarLayout.userToFixedSpacing(
            showsScrollArrows: true,
            regularSpacing: 4
        )

        #expect(withoutArrows.afterScrollView == 16)
        #expect(withoutArrows.afterRightArrow == 16)
        #expect(withArrows.afterScrollView == 4)
        #expect(withArrows.afterRightArrow == 16)
    }

    @Test("Toolbar action titles stay on one line and resist compression")
    func toolbarActionTitleLayout() {
        let button = NSButton(title: "Create PR", target: nil, action: nil)

        ThreadToolbarCapsuleLayout.configureActionButton(button)

        #expect(button.lineBreakMode == .byTruncatingTail)
        #expect(button.cell?.lineBreakMode == .byTruncatingTail)
        #expect(button.contentHuggingPriority(for: .horizontal) == .required)
        #expect(button.contentCompressionResistancePriority(for: .horizontal) == .required)
    }

    @Test("Thread summary preferred width yields before toolbar actions")
    func threadSummaryWidthPriority() {
        let summaryView = NSView()
        let preferredWidth = summaryView.widthAnchor.constraint(
            greaterThanOrEqualToConstant: ThreadToolbarCapsuleLayout.preferredThreadSummaryWidth
        )

        ThreadToolbarCapsuleLayout.configurePreferredThreadSummaryWidth(preferredWidth)

        #expect(preferredWidth.priority == .defaultHigh)
    }

    @Test("Constrained toolbar shrinks thread summary before action title")
    @MainActor
    func constrainedToolbarLayout() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 40))
        let stack = NSStackView(frame: container.bounds)
        let summaryView = NSView()
        let actionButton = NSButton(title: "Create Pull Request", target: nil, action: nil)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        summaryView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        ThreadToolbarCapsuleLayout.configureActionButton(actionButton)

        stack.addArrangedSubview(summaryView)
        stack.addArrangedSubview(actionButton)
        container.addSubview(stack)

        let preferredSummaryWidth = summaryView.widthAnchor.constraint(
            greaterThanOrEqualToConstant: ThreadToolbarCapsuleLayout.preferredThreadSummaryWidth
        )
        ThreadToolbarCapsuleLayout.configurePreferredThreadSummaryWidth(preferredSummaryWidth)
        NSLayoutConstraint.activate([
            preferredSummaryWidth,
            summaryView.heightAnchor.constraint(equalToConstant: 28),
        ])

        let actionIntrinsicWidth = actionButton.intrinsicContentSize.width
        stack.layoutSubtreeIfNeeded()

        #expect(summaryView.frame.width < ThreadToolbarCapsuleLayout.preferredThreadSummaryWidth)
        #expect(actionButton.frame.width >= actionIntrinsicWidth)
    }
}
