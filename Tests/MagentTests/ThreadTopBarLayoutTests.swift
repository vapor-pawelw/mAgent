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
}
