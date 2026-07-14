import Foundation

/// Last-known tmux availability used only to restore sidebar state before the
/// first live session scan completes.
public struct ThreadSessionStateCache: Codable, Sendable, Equatable {
    public var deadSessionsByThreadID: [String: Set<String>]
    public var evictedSessions: Set<String>

    public init(deadSessionsByThreadID: [String: Set<String>], evictedSessions: Set<String>) {
        self.deadSessionsByThreadID = deadSessionsByThreadID
        self.evictedSessions = evictedSessions
    }

    public init(threads: [MagentThread], evictedSessions: Set<String>) {
        deadSessionsByThreadID = Dictionary(
            threads.compactMap { thread in
                guard !thread.sidebarDeadSessions.isEmpty else { return nil }
                return (thread.id.uuidString, thread.sidebarDeadSessions)
            },
            uniquingKeysWith: { $0.union($1) }
        )
        self.evictedSessions = evictedSessions
    }

    /// Applies only entries that still belong to an active thread and one of its
    /// current tabs. Live tmux reconciliation remains authoritative afterward.
    public func restore(into threads: inout [MagentThread]) -> Set<String> {
        var knownSessions = Set<String>()

        for index in threads.indices where !threads[index].isArchived {
            let threadSessions = Set(threads[index].tmuxSessionNames)
            knownSessions.formUnion(threadSessions)

            let cachedDead = deadSessionsByThreadID[threads[index].id.uuidString, default: []]
                .intersection(threadSessions)
            threads[index].cachedDeadSessions = cachedDead
        }

        return evictedSessions.intersection(knownSessions)
    }
}
