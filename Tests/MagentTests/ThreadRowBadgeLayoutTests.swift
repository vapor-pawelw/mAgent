import Testing

@Suite
struct ThreadRowBadgeLayoutTests {

    @Test("Activity age fills one cumulative circle slice per color band")
    func activityAgeMapsToCumulativeCircleSlices() {
        #expect(ThreadRowBadgeLayout.activityColorLevelCount == 6)
        #expect(ThreadRowBadgeLayout.activityColorLevel(forElapsed: 0) == 1)
        #expect(ThreadRowBadgeLayout.activityColorLevel(forElapsed: 900) == 2)
        #expect(ThreadRowBadgeLayout.activityColorLevel(forElapsed: 7_200) == 3)
        #expect(ThreadRowBadgeLayout.activityColorLevel(forElapsed: 28_800) == 4)
        #expect(ThreadRowBadgeLayout.activityColorLevel(forElapsed: 86_400) == 5)
        #expect(ThreadRowBadgeLayout.activityColorLevel(forElapsed: 259_200) == 6)
    }

    @Test("Activity duration sits left of priority so priority stays closer to the row center")
    func bottomLeftOrderKeepsPriorityClosestToCenter() {
        #expect(ThreadRowBadgeLayout.BottomLeftItem.allCases == [.activityDuration, .priority])
    }

    @Test("Movable state indicators preserve their established order in the bottom-right stack")
    func bottomRightOrderPreservesStateIndicatorOrder() {
        #expect(ThreadRowBadgeLayout.BottomRightItem.allCases == [.favorite, .pinned, .hidden, .jiraSync])
    }
}
