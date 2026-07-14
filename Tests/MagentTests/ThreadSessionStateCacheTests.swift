import Foundation
import MagentCore
import Testing

@Suite("Thread session state launch cache")
struct ThreadSessionStateCacheTests {
    @Test("Restores dead and intentionally evicted sessions for current tabs")
    func restoresCurrentSessionState() {
        let threadID = UUID()
        var threads = [makeThread(id: threadID, sessions: ["live", "dead", "evicted"])]
        let cache = ThreadSessionStateCache(
            deadSessionsByThreadID: [threadID.uuidString: ["dead", "evicted"]],
            evictedSessions: ["evicted"]
        )

        let restoredEvictions = cache.restore(into: &threads)

        #expect(threads[0].deadSessions.isEmpty)
        #expect(threads[0].cachedDeadSessions == ["dead", "evicted"])
        #expect(restoredEvictions == ["evicted"])
    }

    @Test("Drops state for removed threads and tabs")
    func dropsStaleSessionState() {
        let currentThreadID = UUID()
        let removedThreadID = UUID()
        var threads = [makeThread(id: currentThreadID, sessions: ["current"])]
        let cache = ThreadSessionStateCache(
            deadSessionsByThreadID: [
                currentThreadID.uuidString: ["removed-tab"],
                removedThreadID.uuidString: ["removed-thread-session"],
            ],
            evictedSessions: ["removed-tab", "removed-thread-session"]
        )

        let restoredEvictions = cache.restore(into: &threads)

        #expect(threads[0].cachedDeadSessions.isEmpty)
        #expect(restoredEvictions.isEmpty)
    }

    @Test("Restores intentional eviction even before a dead-session scan records it")
    func restoresEvictionIndependentlyFromDeadState() {
        let threadID = UUID()
        var threads = [makeThread(id: threadID, sessions: ["evicted"])]
        let cache = ThreadSessionStateCache(
            deadSessionsByThreadID: [:],
            evictedSessions: ["evicted"]
        )

        let restoredEvictions = cache.restore(into: &threads)

        #expect(threads[0].deadSessions.isEmpty)
        #expect(threads[0].cachedDeadSessions.isEmpty)
        #expect(restoredEvictions == ["evicted"])
    }

    @Test("Captures only threads with dead sessions")
    func capturesCurrentSessionState() {
        var deadThread = makeThread(id: UUID(), sessions: ["dead"])
        deadThread.deadSessions = ["dead"]
        let liveThread = makeThread(id: UUID(), sessions: ["live"])

        let cache = ThreadSessionStateCache(
            threads: [deadThread, liveThread],
            evictedSessions: ["dead"]
        )

        #expect(cache.deadSessionsByThreadID == [deadThread.id.uuidString: ["dead"]])
        #expect(cache.evictedSessions == ["dead"])
    }

    @Test("Cached dead sessions affect sidebar presentation without becoming live dead state")
    func cachedDeadStateIsPresentationOnly() {
        var thread = makeThread(id: UUID(), sessions: ["first", "second"])
        thread.cachedDeadSessions = ["first", "second"]

        #expect(thread.hasAllSessionsDead)
        #expect(thread.deadSessions.isEmpty)
    }

    @Test("Capturing duplicate thread IDs merges their cached session state")
    func mergesDuplicateThreadIDs() {
        let threadID = UUID()
        var first = makeThread(id: threadID, sessions: ["first"])
        first.deadSessions = ["first"]
        var second = makeThread(id: threadID, sessions: ["second"])
        second.deadSessions = ["second"]

        let cache = ThreadSessionStateCache(threads: [first, second], evictedSessions: [])

        #expect(cache.deadSessionsByThreadID[threadID.uuidString] == ["first", "second"])
    }

    private func makeThread(id: UUID, sessions: [String]) -> MagentThread {
        MagentThread(
            id: id,
            projectId: UUID(),
            name: "thread",
            worktreePath: "/tmp/thread",
            branchName: "thread",
            tmuxSessionNames: sessions
        )
    }
}
