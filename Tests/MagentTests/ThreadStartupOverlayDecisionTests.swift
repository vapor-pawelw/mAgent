import Testing
import MagentCore

@Suite
struct ThreadStartupOverlayDecisionTests {
    @Test
    func warmTerminalRevisitSkipsOverlayTracking() {
        #expect(ThreadStartupOverlayDecision.action(
            isRestoringTerminalTab: true,
            requiresStartupOverlay: false,
            canFastPathSelectedSession: true
        ) == .skip)
    }

    @Test
    func explicitStartupHandoffTracksEvenWhenSessionCanFastPath() {
        #expect(ThreadStartupOverlayDecision.action(
            isRestoringTerminalTab: true,
            requiresStartupOverlay: true,
            canFastPathSelectedSession: true
        ) == .track)
    }

    @Test
    func coldTerminalRestoreTracksOverlay() {
        #expect(ThreadStartupOverlayDecision.action(
            isRestoringTerminalTab: true,
            requiresStartupOverlay: false,
            canFastPathSelectedSession: false
        ) == .track)
    }

    @Test
    func nonTerminalRestoreSkipsTerminalOverlayTracking() {
        #expect(ThreadStartupOverlayDecision.action(
            isRestoringTerminalTab: false,
            requiresStartupOverlay: false,
            canFastPathSelectedSession: false
        ) == .skip)
    }
}
