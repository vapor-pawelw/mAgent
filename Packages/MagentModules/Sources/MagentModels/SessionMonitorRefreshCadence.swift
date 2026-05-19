import Foundation

public enum SessionMonitorRefreshCadence {
    public static let monitorIntervalSeconds: TimeInterval = 5.0
    public static let gitStateIntervalTicks = 10
    public static let statusSyncIntervalTicks = 60

    public static func resetGitStateCounter(_ counter: inout Int) {
        counter = 0
    }

    public static func resetStatusSyncCounters(prCounter: inout Int, jiraCounter: inout Int) {
        prCounter = 0
        jiraCounter = 0
    }
}
