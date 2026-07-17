import Foundation
import Testing
@testable import MagentCore

@Suite("Chat streaming text mutation")
struct ChatStreamingTextMutationTests {
    @Test("Prefix growth restyles only a bounded tail")
    func boundsRestyledTail() throws {
        let previous = String(repeating: "a", count: 4_000)
        let next = previous + " appended"

        let plan = ChatStreamingTextMutationPlanner.plan(previous: previous, next: next)
        guard case .appendStyledTail(let offset, let replacement) = plan else {
            Issue.record("Expected a styled-tail append")
            return
        }

        #expect(offset == 3_744)
        #expect(replacement.count == 265)
    }

    @Test("A paragraph boundary narrows the restyled region")
    func startsAtRecentParagraphBoundary() {
        let previous = String(repeating: "old ", count: 100) + "\n\nCurrent paragraph"
        let next = previous + " continues"

        let plan = ChatStreamingTextMutationPlanner.plan(previous: previous, next: next)
        guard case .appendStyledTail(_, let replacement) = plan else {
            Issue.record("Expected a styled-tail append")
            return
        }

        #expect(replacement == "Current paragraph continues")
    }

    @Test("Open fenced code appends using the established code attributes")
    func inheritsOpenFenceAttributes() {
        let previous = "```swift\nlet value = 1"
        let plan = ChatStreamingTextMutationPlanner.plan(
            previous: previous,
            next: previous + "\nprint(value)"
        )

        #expect(plan == .appendUsingPreviousAttributes(delta: "\nprint(value)"))
    }

    @Test("Reconciliation that is not prefix growth requests replacement")
    func replacesDivergentText() {
        #expect(ChatStreamingTextMutationPlanner.plan(previous: "draft", next: "final") == .replace)
    }

    @Test("Render planning finds a streamed response before its loading placeholder")
    func detectsPenultimateStreamingMessage() {
        let user = PersistedChatMessage(role: .user, text: "Question")
        let responseID = UUID()
        let response = PersistedChatMessage(id: responseID, role: .assistant, text: "Partial")
        let loading = PersistedChatMessage(role: .assistant, text: "Thinking...")
        let updatedResponse = PersistedChatMessage(id: responseID, role: .assistant, text: "Partial answer")

        let plan = ChatMessageRenderPlanner.plan(
            previous: [user, response, loading],
            next: [user, updatedResponse, loading]
        )

        #expect(plan == .incremental(removeTailCount: 0, appendRange: 3..<3, changedIndices: [1]))
    }
}
