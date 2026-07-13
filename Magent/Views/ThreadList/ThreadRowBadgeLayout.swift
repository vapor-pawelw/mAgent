enum ThreadRowBadgeLayout {
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
