import MagentCore
import Testing

@Suite("ThreadTabFocusResolver")
struct ThreadTabFocusResolverTests {
    @Test("Terminal tabs focus embedded terminal surface")
    func terminalFocusTarget() {
        #expect(ThreadTabFocusResolver.focusTarget(for: .terminal) == .terminalSurface)
    }

    @Test("Web tabs focus web content")
    func webFocusTarget() {
        #expect(ThreadTabFocusResolver.focusTarget(for: .web) == .webContent)
    }

    @Test("Draft tabs focus prompt editor")
    func draftFocusTarget() {
        #expect(ThreadTabFocusResolver.focusTarget(for: .draft) == .draftPrompt)
    }
}
