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

    @Test("Leading status items keep activity before priority")
    func leadingStatusOrderKeepsActivityBeforePriority() {
        #expect(ThreadRowBadgeLayout.LeadingStatusItem.allCases == [.activityDuration, .priority])
    }

    @Test("Trailing status indicators preserve their established order")
    func trailingStatusOrderPreservesStateIndicatorOrder() {
        #expect(ThreadRowBadgeLayout.TrailingStatusItem.allCases == [.favorite, .pinned, .hidden, .jiraSync])
    }
}
