import AppKit
import CoreGraphics
import GhosttyBridge
import Testing

@Suite
struct TerminalSurfaceSizingTests {

    @Test
    func pixelSizeTracksBackingScaleChangesWithoutPointSizeChange() {
        let pointSize = CGSize(width: 800, height: 600)

        #expect(TerminalSurfaceSizing.pixelSize(for: pointSize, scale: 2.0)?.width == 1600)
        #expect(TerminalSurfaceSizing.pixelSize(for: pointSize, scale: 2.0)?.height == 1200)
        #expect(TerminalSurfaceSizing.pixelSize(for: pointSize, scale: 1.0)?.width == 800)
        #expect(TerminalSurfaceSizing.pixelSize(for: pointSize, scale: 1.0)?.height == 600)
    }

    @Test
    func pixelSizeRejectsInvalidGeometry() {
        #expect(TerminalSurfaceSizing.pixelSize(for: CGSize(width: 0, height: 600), scale: 2.0) == nil)
        #expect(TerminalSurfaceSizing.pixelSize(for: CGSize(width: 800, height: 0), scale: 2.0) == nil)
        #expect(TerminalSurfaceSizing.pixelSize(for: CGSize(width: 800, height: 600), scale: 0) == nil)
    }

    @Test
    @MainActor
    func escapeKeyNotifiesHostAfterTerminalSteering() throws {
        let view = TerminalSurfaceView(workingDirectory: "/tmp")
        var notificationCount = 0
        view.onEscapeKey = {
            notificationCount += 1
        }
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{1B}",
                charactersIgnoringModifiers: "\u{1B}",
                isARepeat: false,
                keyCode: 53
            )
        )

        view.keyDown(with: event)

        #expect(notificationCount == 1)
    }

    @Test
    func serverRestartRestoresOnlyAttachedViewsWithLiveSessions() {
        let liveSessions: Set<String> = ["visible"]

        #expect(TmuxSurfaceRestartPolicy.resolution(
            sessionName: "visible",
            isAttachedToWindow: true,
            liveTmuxSessions: liveSessions
        ) == .restore)
        #expect(TmuxSurfaceRestartPolicy.resolution(
            sessionName: "visible",
            isAttachedToWindow: false,
            liveTmuxSessions: liveSessions
        ) == .discard)
        #expect(TmuxSurfaceRestartPolicy.resolution(
            sessionName: "dead",
            isAttachedToWindow: true,
            liveTmuxSessions: liveSessions
        ) == .keepPending)
    }
}
