import Foundation

enum TabPinningState {
    static func preferredPrimarySession(
        sessions: [String],
        agentSessions: Set<String>,
        canonicalPrimarySession: String?
    ) -> String {
        if let canonicalPrimarySession,
           sessions.contains(canonicalPrimarySession),
           !agentSessions.contains(canonicalPrimarySession) {
            return canonicalPrimarySession
        }
        if let firstNonAgent = sessions.first(where: { !agentSessions.contains($0) }) {
            return firstNonAgent
        }
        if let canonicalPrimarySession, sessions.contains(canonicalPrimarySession) {
            return canonicalPrimarySession
        }
        return sessions.first ?? ""
    }

    static func sessionDisplayOrder(
        sessions: [String],
        canonicalPrimarySession: String?
    ) -> (primary: String, movable: [String]) {
        let primary = canonicalPrimarySession
            ?? sessions.first
            ?? ""
        let movable = sessions.filter { $0 != primary }
        return (primary, movable)
    }

    static func orderedMovableSessions(
        movableSessions: [String],
        pinnedSessions: Set<String>
    ) -> [String] {
        let pinned = movableSessions.filter { pinnedSessions.contains($0) }
        let unpinned = movableSessions.filter { !pinnedSessions.contains($0) }
        return pinned + unpinned
    }
    static func clampedPinnedBoundary(
        _ boundary: Int,
        fixedCount: Int,
        totalCount: Int
    ) -> Int {
        let safeFixed = max(0, min(fixedCount, totalCount))
        return max(safeFixed, min(boundary, totalCount))
    }

    static func pinnedBoundary(
        fixedCount: Int,
        pinnedMovableCount: Int,
        totalCount: Int
    ) -> Int {
        let safeFixed = max(0, min(fixedCount, totalCount))
        let rawBoundary = safeFixed + max(0, pinnedMovableCount)
        return clampedPinnedBoundary(rawBoundary, fixedCount: safeFixed, totalCount: totalCount)
    }

    static func isPinnedMovableIndex(
        _ index: Int,
        pinnedBoundary: Int,
        fixedCount: Int
    ) -> Bool {
        index >= fixedCount && index < pinnedBoundary
    }
}
