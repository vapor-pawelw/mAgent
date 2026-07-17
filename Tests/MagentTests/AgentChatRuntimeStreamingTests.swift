import Foundation
import MagentCore
import Testing

@Suite("Agent chat runtime streaming")
struct AgentChatRuntimeStreamingTests {
    @Test("JSON lines are decoded across chunks and partial data is retained")
    func jsonLineBufferHandlesChunkBoundaries() {
        var buffer = AgentChatJSONLineBuffer()

        #expect(buffer.append(Data(#"{"id":1}"#.utf8)).isEmpty)
        #expect(buffer.remainingText == #"{"id":1}"#)

        let lines = buffer.append(Data("\n{\"id\":2}\n{\"id\":".utf8))

        #expect(lines == [#"{"id":1}"#, #"{"id":2}"#])
        #expect(buffer.remainingText == #"{"id":"#)
        #expect(buffer.append(Data("3}\n".utf8)) == [#"{"id":3}"#])
        #expect(buffer.remainingText.isEmpty)
    }

    @Test("Burst output returns all complete lines in order")
    func jsonLineBufferHandlesBurstyOutput() {
        var buffer = AgentChatJSONLineBuffer()
        let expected = (0..<1_000).map { "line-\($0)" }
        let payload = expected.joined(separator: "\n") + "\n"

        let lines = buffer.append(Data(payload.utf8))

        #expect(lines == expected)
        #expect(buffer.remainingText.isEmpty)
    }

    @Test("Streaming deltas are coalesced without full-text snapshots")
    @MainActor
    func streamingDeltasAreCoalesced() async throws {
        var received: [AgentChatStreamingUpdate] = []
        let coalescer = AgentChatStreamingCoalescer(deliveryInterval: .milliseconds(30)) {
            received.append($0)
        }

        coalescer.append(delta: "one ", itemID: "message")
        coalescer.append(delta: "two ", itemID: "message")
        coalescer.append(delta: "three", itemID: "message")
        try await Task.sleep(for: .milliseconds(100))

        #expect(received == [
            AgentChatStreamingUpdate(
                itemID: "message",
                text: "one two three",
                textKind: .delta,
                isFinal: false
            ),
        ])
    }

    @Test("Final replacement supersedes an undelivered delta")
    @MainActor
    func finalReplacementSupersedesPendingDelta() async throws {
        var received: [AgentChatStreamingUpdate] = []
        let coalescer = AgentChatStreamingCoalescer(deliveryInterval: .milliseconds(80)) {
            received.append($0)
        }

        coalescer.append(delta: "draft", itemID: "message")
        coalescer.finish(itemID: "message", finalText: "final answer")
        try await Task.sleep(for: .milliseconds(150))

        #expect(received == [
            AgentChatStreamingUpdate(
                itemID: "message",
                text: "final answer",
                textKind: .replacement,
                isFinal: true
            ),
        ])
    }
}
