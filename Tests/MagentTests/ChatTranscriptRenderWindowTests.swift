import Testing
@testable import MagentCore

@Suite("Chat transcript render window")
struct ChatTranscriptRenderWindowTests {
    @Test("Latest page retains only the configured number of messages")
    func latestPageIsBounded() {
        let window = ChatTranscriptRenderWindow(messageCount: 1_000, pageSize: 160)

        #expect(window.range == 840..<1_000)
        #expect(window.hasOlderMessages)
        #expect(!window.hasNewerMessages)
    }

    @Test("Previous and next paging exposes the whole transcript without growing the window")
    func pagesInBothDirections() {
        let latest = ChatTranscriptRenderWindow(messageCount: 450, pageSize: 160)
        let previousEnd = latest.previousPageEnd()
        let previous = ChatTranscriptRenderWindow(
            messageCount: 450,
            pageSize: 160,
            endingAt: previousEnd
        )

        #expect(previous.range == 130..<290)
        #expect(previous.hasOlderMessages)
        #expect(previous.hasNewerMessages)
        #expect(previous.nextPageEnd(messageCount: 450, pageSize: 160) == nil)
    }

    @Test("Oldest partial page stays within transcript bounds")
    func oldestPageIsClamped() {
        let window = ChatTranscriptRenderWindow(messageCount: 90, pageSize: 160, endingAt: 30)

        #expect(window.range == 0..<30)
        #expect(!window.hasOlderMessages)
        #expect(window.hasNewerMessages)
    }
}
