import Testing

@Suite
struct TabPinningStateTests {
    @Test
    func pinnedBoundaryIncludesFixedTabs() {
        let boundary = TabPinningState.pinnedBoundary(
            fixedCount: 2,
            pinnedMovableCount: 0,
            totalCount: 7
        )
        #expect(boundary == 2)
    }

    @Test
    func pinnedBoundaryClampsToTotalCount() {
        let boundary = TabPinningState.pinnedBoundary(
            fixedCount: 2,
            pinnedMovableCount: 10,
            totalCount: 5
        )
        #expect(boundary == 5)
    }

    @Test
    func pinnedMovableIndexExcludesFixedTabs() {
        #expect(!TabPinningState.isPinnedMovableIndex(0, pinnedBoundary: 4, fixedCount: 2))
        #expect(!TabPinningState.isPinnedMovableIndex(1, pinnedBoundary: 4, fixedCount: 2))
        #expect(TabPinningState.isPinnedMovableIndex(2, pinnedBoundary: 4, fixedCount: 2))
        #expect(TabPinningState.isPinnedMovableIndex(3, pinnedBoundary: 4, fixedCount: 2))
        #expect(!TabPinningState.isPinnedMovableIndex(4, pinnedBoundary: 4, fixedCount: 2))
    }

    @Test
    func supportsFutureAdditionalPermanentTabs() {
        let boundary = TabPinningState.pinnedBoundary(
            fixedCount: 4,
            pinnedMovableCount: 2,
            totalCount: 10
        )
        #expect(boundary == 6)
        #expect(!TabPinningState.isPinnedMovableIndex(0, pinnedBoundary: boundary, fixedCount: 4))
        #expect(!TabPinningState.isPinnedMovableIndex(3, pinnedBoundary: boundary, fixedCount: 4))
        #expect(TabPinningState.isPinnedMovableIndex(4, pinnedBoundary: boundary, fixedCount: 4))
        #expect(TabPinningState.isPinnedMovableIndex(5, pinnedBoundary: boundary, fixedCount: 4))
        #expect(!TabPinningState.isPinnedMovableIndex(6, pinnedBoundary: boundary, fixedCount: 4))
    }

    @Test
    func clampedBoundaryNeverDropsBelowFixedTabs() {
        let clamped = TabPinningState.clampedPinnedBoundary(
            1,
            fixedCount: 3,
            totalCount: 8
        )
        #expect(clamped == 3)
    }

    @Test
    func sessionDisplayOrderKeepsCanonicalPrimaryOutOfMovableTabs() {
        let result = TabPinningState.sessionDisplayOrder(
            sessions: ["s1", "s2", "s3"],
            canonicalPrimarySession: "s2"
        )
        #expect(result.primary == "s2")
        #expect(result.movable == ["s1", "s3"])
    }

    @Test
    func orderedMovableSessionsPlacesPinnedBeforeUnpinnedWithoutReorderingWithinGroups() {
        let ordered = TabPinningState.orderedMovableSessions(
            movableSessions: ["a", "b", "c", "d"],
            pinnedSessions: ["d", "b"]
        )
        #expect(ordered == ["b", "d", "a", "c"])
    }

    @Test
    func preferredPrimarySessionPrefersNonAgentCanonical() {
        let primary = TabPinningState.preferredPrimarySession(
            sessions: ["s1", "s2", "s3"],
            agentSessions: ["s3"],
            canonicalPrimarySession: "s2"
        )
        #expect(primary == "s2")
    }

    @Test
    func preferredPrimarySessionFallsBackToFirstNonAgentWhenCanonicalIsAgent() {
        let primary = TabPinningState.preferredPrimarySession(
            sessions: ["s-agent", "s-term", "s-agent-2"],
            agentSessions: ["s-agent", "s-agent-2"],
            canonicalPrimarySession: "s-agent"
        )
        #expect(primary == "s-term")
    }

    @Test
    func detectsWhenFixedTerminalNeedsPlainFallback() {
        #expect(TabPinningState.needsPlainPrimaryFallback(
            sessions: ["s-agent", "s-agent-2"],
            agentSessions: ["s-agent", "s-agent-2"]
        ))
        #expect(!TabPinningState.needsPlainPrimaryFallback(
            sessions: ["s-terminal", "s-agent"],
            agentSessions: ["s-agent"]
        ))
        #expect(!TabPinningState.needsPlainPrimaryFallback(
            sessions: [],
            agentSessions: []
        ))
    }
}
