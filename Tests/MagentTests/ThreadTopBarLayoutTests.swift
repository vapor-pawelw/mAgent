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
        let groups = ThreadTopBarLayout.tabGroups(tabCount: 6, fixedCount: 2, pinnedBoundary: 4)

        #expect(groups.fixed == 0..<2)
        #expect(groups.pinned == 2..<4)
        #expect(groups.unpinned == 4..<6)
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
