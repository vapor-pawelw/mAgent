enum ThreadRowBadgeLayout {
    static let activityColorLevelCount = 6

    static func activityColorLevel(forElapsed elapsed: Int) -> Int {
        switch elapsed {
        case ..<900: 1
        case ..<7_200: 2
        case ..<28_800: 3
        case ..<86_400: 4
        case ..<259_200: 5
        default: 6
        }
    }

    enum BottomLeftItem: CaseIterable {
        case activityDuration
        case priority
    }

    enum BottomRightItem: CaseIterable {
        case favorite
        case pinned
        case hidden
        case jiraSync
    }
}
