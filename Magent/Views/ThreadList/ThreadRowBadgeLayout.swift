enum ThreadRowBadgeLayout {
    static func priorityOptionLabel(
        _ label: String,
        level: Int,
        jiraPriority: Int?,
        jiraAnnotation: String
    ) -> String {
        guard level == jiraPriority else { return label }
        return "\(label) \(jiraAnnotation)"
    }

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

    enum LeadingStatusItem: CaseIterable {
        case priority
    }

    enum TrailingStatusItem: CaseIterable {
        case favorite
        case pinned
        case hidden
        case jiraSync
        case activityDuration
    }
}
