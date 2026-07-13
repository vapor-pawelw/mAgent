import Testing

@Suite
struct ThreadRowBadgeLayoutTests {

    @Test("Activity duration sits left of priority so priority stays closer to the row center")
    func bottomLeftOrderKeepsPriorityClosestToCenter() {
        #expect(ThreadRowBadgeLayout.BottomLeftItem.allCases == [.activityDuration, .priority])
    }

    @Test("Movable state indicators preserve their established order in the bottom-right stack")
    func bottomRightOrderPreservesStateIndicatorOrder() {
        #expect(ThreadRowBadgeLayout.BottomRightItem.allCases == [.favorite, .pinned, .hidden, .jiraSync])
    }
}
