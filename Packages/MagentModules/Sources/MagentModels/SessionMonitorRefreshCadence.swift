import Foundation

public enum SessionMonitorRefreshCadence {
    public static let monitorIntervalSeconds: TimeInterval = 5.0
    public static let gitStateIntervalTicks = 10
    public static let statusSyncIntervalTicks = 60
    public static let statusSyncIntervalSeconds = monitorIntervalSeconds * TimeInterval(statusSyncIntervalTicks)

    public static func resetGitStateCounter(_ counter: inout Int) {
        counter = 0
    }

    public static func resetStatusSyncCounters(prCounter: inout Int, jiraCounter: inout Int) {
        prCounter = 0
        jiraCounter = 0
    }
}

public enum JiraTicketRefreshReason: Equatable {
    case appLaunch
    case detectedTicketChange
    case displayedStatusSync
    case agentCompletion
    case manual
    case settingsEnabled

    public var bypassesCache: Bool {
        switch self {
        case .appLaunch, .displayedStatusSync, .agentCompletion, .manual:
            true
        case .detectedTicketChange, .settingsEnabled:
            false
        }
    }
}

public enum JiraTicketRefreshPolicy {
    /// How long a cached ticket entry can satisfy opportunistic refreshes.
    /// Scheduled status sync and agent-completion refreshes bypass this cache.
    public static let displayedTicketCacheTTL: TimeInterval = 6 * 60

    public static func needsVerification(
        cachedVerifiedAt: Date?,
        now: Date,
        reason: JiraTicketRefreshReason
    ) -> Bool {
        guard let cachedVerifiedAt else { return true }
        if reason.bypassesCache { return true }
        return cachedVerifiedAt < now.addingTimeInterval(-displayedTicketCacheTTL)
    }
}
