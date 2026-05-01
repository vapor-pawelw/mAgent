import Testing
import MagentCore

@Suite("Chat timestamp presentation")
struct ChatTimestampPresentationTests {
    @Test("Relative mode shows relative time by default")
    func relativeModeDefault() {
        let text = ChatTimestampPresentation.displayText(
            mode: .relative,
            relativeText: "2 minutes ago",
            exactText: "May 1, 2026 at 11:45:10 AM",
            hoverText: nil
        )
        #expect(text == "2 minutes ago")
    }

    @Test("Relative mode prefers hover metadata when available")
    func relativeModeWithHoverMetadata() {
        let text = ChatTimestampPresentation.displayText(
            mode: .relative,
            relativeText: "2 minutes ago",
            exactText: "May 1, 2026 at 11:45:10 AM",
            hoverText: "GPT 5.3 · high"
        )
        #expect(text == "GPT 5.3 · high")
    }

    @Test("Exact mode always shows full timestamp")
    func exactModeAlwaysWins() {
        let text = ChatTimestampPresentation.displayText(
            mode: .exact,
            relativeText: "2 minutes ago",
            exactText: "May 1, 2026 at 11:45:10 AM",
            hoverText: "GPT 5.3 · high"
        )
        #expect(text == "May 1, 2026 at 11:45:10 AM")
    }

    @Test("Display mode toggles back and forth")
    func modeToggle() {
        var mode: ChatTimestampDisplayMode = .relative
        mode.toggle()
        #expect(mode == .exact)
        mode.toggle()
        #expect(mode == .relative)
    }
}
