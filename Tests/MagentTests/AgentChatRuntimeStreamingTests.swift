import Foundation
import MagentCore
import Testing
@testable import UtilityCore

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

    @Test("Flushing delivers buffered assistant text before the following tool activity")
    @MainActor
    func flushPreservesProtocolOrder() async throws {
        var received: [AgentChatStreamingUpdate] = []
        let coalescer = AgentChatStreamingCoalescer(deliveryInterval: .seconds(1)) {
            received.append($0)
        }

        coalescer.append(delta: "Checking first.", itemID: "message")
        coalescer.flush()
        DispatchQueue.main.async {
            received.append(AgentChatStreamingUpdate(itemID: "tool", text: "Run command", isFinal: false))
        }
        try await Task.sleep(for: .milliseconds(30))

        #expect(received.map(\.itemID) == ["message", "tool"])
    }

    @Test("Codex reports active work as soon as a turn starts")
    func codexTurnStartReplacesStartupStatus() {
        #expect(AgentChatStatusUpdate.codexAppServerNotification(method: "thread/started") == nil)
        #expect(AgentChatStatusUpdate.codexAppServerNotification(method: "turn/started") == .working)
        #expect(AgentChatStatusUpdate.codexAppServerNotification(method: "item/started") == nil)
    }

    @Test("Parallel agent startup becomes visible tool activity")
    func parallelAgentStartupIsStreamed() throws {
        let item: [String: Any] = [
            "id": "collab-1",
            "type": "collabAgentToolCall",
            "tool": "spawnAgent",
            "status": "inProgress",
            "prompt": "Inspect the persistence flow",
            "receiverThreadIds": ["child-1"],
            "agentsStates": ["child-1": ["status": "running"]],
        ]

        let update = try #require(CodexAppServerLiveItemUpdate.update(for: item, isFinal: false))

        #expect(update.itemID == "collab-1")
        #expect(update.isFinal == false)
        #expect(update.toolEvent?.kind == .call)
        #expect(update.toolEvent?.name == "spawn_agent")
        #expect(update.toolEvent?.arguments?.contains("Inspect the persistence flow") == true)
        #expect(CodexAppServerLiveItemUpdate.receiverThreadIDs(from: item) == ["child-1"])
    }

    @Test("A subagent command completion replaces its running activity")
    func subagentCommandCompletionIsStreamed() throws {
        let item: [String: Any] = [
            "id": "command-1",
            "type": "commandExecution",
            "command": "rg persistence",
            "cwd": "/repo",
            "status": "completed",
            "aggregatedOutput": "2 matches",
            "exitCode": 0,
        ]

        let update = try #require(CodexAppServerLiveItemUpdate.update(for: item, isFinal: true))

        #expect(update.itemID == "command-1")
        #expect(update.isFinal)
        #expect(update.toolEvent?.kind == .result)
        #expect(update.toolEvent?.name == "exec_command")
        #expect(update.toolEvent?.output == "2 matches")
        #expect(update.toolEvent?.exitCode == "0")
    }

    @Test("Failed commands retain their actual exit code")
    func failedCommandExitCodeIsPreserved() throws {
        let item: [String: Any] = [
            "id": "command-2",
            "type": "commandExecution",
            "command": "missing-tool",
            "cwd": "/repo",
            "status": "failed",
            "aggregatedOutput": "command not found",
            "exitCode": 127,
        ]

        let update = try #require(CodexAppServerLiveItemUpdate.update(for: item, isFinal: true))

        #expect(update.toolEvent?.exitCode == "127")
    }

    @Test("Subagent activity cannot establish its own parent relationship")
    func subagentActivityDoesNotSelfAuthorize() {
        let item: [String: Any] = [
            "id": "activity-1",
            "type": "subAgentActivity",
            "agentThreadId": "unrelated-child",
            "agentPath": "/root/worker",
            "kind": "started",
        ]

        #expect(CodexAppServerLiveItemUpdate.receiverThreadIDs(from: item).isEmpty)
    }

    @Test("Early child activity is released only after the parent authorizes that thread")
    func earlyChildActivityIsBufferedUntilSpawnConfirmation() throws {
        var router = CodexAppServerLiveItemRouter()
        let childUpdate = try #require(CodexAppServerLiveItemUpdate.update(
            for: [
                "id": "command-1",
                "type": "commandExecution",
                "command": "rg persistence",
                "cwd": "/repo",
                "status": "inProgress",
            ],
            isFinal: false,
            sourceThreadID: "child-1"
        ))
        let spawnUpdate = try #require(CodexAppServerLiveItemUpdate.update(
            for: [
                "id": "collab-1",
                "type": "collabAgentToolCall",
                "tool": "spawnAgent",
                "status": "completed",
                "receiverThreadIds": ["child-1"],
                "agentsStates": ["child-1": ["status": "running"]],
            ],
            isFinal: true
        ))

        #expect(childUpdate.itemID == "child-1:command-1")
        #expect(router.route(
            childUpdate,
            eventThreadID: "child-1",
            rootThreadID: "root",
            newlyRelatedThreadIDs: []
        ).isEmpty)
        #expect(router.route(
            spawnUpdate,
            eventThreadID: "root",
            rootThreadID: "root",
            newlyRelatedThreadIDs: ["child-1"]
        ).map(\.itemID) == ["child-1:command-1", "collab-1"])
    }

    @Test("A null MCP error does not turn a successful result into a failure")
    func nullMCPErrorIsIgnored() throws {
        let item: [String: Any] = [
            "id": "mcp-1",
            "type": "mcpToolCall",
            "server": "files",
            "tool": "read",
            "status": "completed",
            "arguments": ["path": "/repo/file"],
            "error": NSNull(),
            "result": ["content": "ok"],
        ]

        let update = try #require(CodexAppServerLiveItemUpdate.update(for: item, isFinal: true))

        #expect(update.toolEvent?.exitCode == "0")
        #expect(update.toolEvent?.output?.contains("ok") == true)
    }
}
