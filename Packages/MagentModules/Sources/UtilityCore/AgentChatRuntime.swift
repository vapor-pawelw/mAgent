import Foundation
import MagentModels
import os
import ShellInfra

public nonisolated struct AgentChatExecutionResult: Sendable, Equatable {
    public let assistantText: String
    public let conversationSessionID: String?
    public let deferredSteerInputs: [AgentChatSteerInput]

    public init(
        assistantText: String,
        conversationSessionID: String?,
        deferredSteerInputs: [AgentChatSteerInput] = []
    ) {
        self.assistantText = assistantText
        self.conversationSessionID = conversationSessionID
        self.deferredSteerInputs = deferredSteerInputs
    }
}

public nonisolated struct AgentChatSteerInput: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

public nonisolated final class AgentChatSteerChannel: Sendable {
    private struct State: Sendable {
        var pendingInputs: [AgentChatSteerInput] = []
        var inFlightInputsByID: [UUID: AgentChatSteerInput] = [:]
        var inFlightInputOrder: [UUID] = []
        var isClosed = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let submissionSemaphore = DispatchSemaphore(value: 0)

    public init() {}

    @discardableResult
    public func submit(_ input: AgentChatSteerInput) -> Bool {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = AgentChatSteerInput(id: input.id, text: trimmed)
        let accepted = state.withLock { state in
            guard !state.isClosed else { return false }
            state.pendingInputs.append(normalized)
            return true
        }
        if accepted {
            submissionSemaphore.signal()
        }
        return accepted
    }

    func popFirst() -> AgentChatSteerInput? {
        state.withLock { state in
            guard !state.pendingInputs.isEmpty else { return nil }
            let input = state.pendingInputs.removeFirst()
            state.inFlightInputsByID[input.id] = input
            state.inFlightInputOrder.append(input.id)
            return input
        }
    }

    func prepend(_ input: AgentChatSteerInput) {
        state.withLock { state in
            guard !state.isClosed else { return }
            state.inFlightInputsByID.removeValue(forKey: input.id)
            state.inFlightInputOrder.removeAll { $0 == input.id }
            state.pendingInputs.insert(input, at: 0)
        }
    }

    func acknowledge(id: UUID) {
        state.withLock { state in
            state.inFlightInputsByID.removeValue(forKey: id)
            state.inFlightInputOrder.removeAll { $0 == id }
        }
    }

    func waitForSubmission(timeout: DispatchTime) -> DispatchTimeoutResult {
        submissionSemaphore.wait(timeout: timeout)
    }

    public func closeAndDrain() -> [AgentChatSteerInput] {
        state.withLock { state in
            state.isClosed = true
            let inFlightInputs = state.inFlightInputOrder.compactMap {
                state.inFlightInputsByID[$0]
            }
            defer {
                state.pendingInputs.removeAll()
                state.inFlightInputsByID.removeAll()
                state.inFlightInputOrder.removeAll()
            }
            return inFlightInputs + state.pendingInputs
        }
    }
}

public nonisolated struct AgentChatStreamingUpdate: Sendable, Equatable {
    public nonisolated enum TextKind: Sendable, Equatable {
        case delta
        case replacement
    }

    public let itemID: String
    public let text: String
    public let textKind: TextKind
    public let isFinal: Bool
    public let toolEvent: PersistedChatToolEvent?

    public init(
        itemID: String,
        text: String,
        textKind: TextKind = .replacement,
        isFinal: Bool,
        toolEvent: PersistedChatToolEvent? = nil
    ) {
        self.itemID = itemID
        self.text = text
        self.textKind = textKind
        self.isFinal = isFinal
        self.toolEvent = toolEvent
    }
}

public nonisolated enum AgentChatStatusUpdate: Sendable, Equatable {
    case startingCodex
    case working

    static func codexAppServerNotification(method: String) -> Self? {
        method == "turn/started" ? .working : nil
    }
}

nonisolated enum CodexAppServerLiveItemUpdate {
    static func update(
        for item: [String: Any],
        isFinal: Bool,
        sourceThreadID: String? = nil
    ) -> AgentChatStreamingUpdate? {
        guard let itemID = normalizedString(item["id"]),
              let type = item["type"] as? String else {
            return nil
        }

        let tool: (name: String, arguments: String, output: String?, failed: Bool, exitCode: String?)? = switch type {
        case "commandExecution": commandExecutionTool(from: item)
        case "fileChange": fileChangeTool(from: item)
        case "mcpToolCall": mcpTool(from: item)
        case "dynamicToolCall": dynamicTool(from: item)
        case "collabAgentToolCall": collaborationTool(from: item)
        case "subAgentActivity": subagentActivityTool(from: item)
        default: nil
        }
        guard let tool else { return nil }
        let arguments = sourceThreadID.map {
            argumentsByAddingSourceThreadID($0, to: tool.arguments)
        } ?? tool.arguments

        let event: PersistedChatToolEvent
        let text: String
        if isFinal {
            let output = tool.output ?? "Completed"
            event = PersistedChatToolEvent(
                kind: .result,
                name: tool.name,
                arguments: arguments,
                output: output,
                exitCode: tool.exitCode ?? (tool.failed ? "1" : "0")
            )
            text = ChatToolTranscriptFormatter.toolResultText(
                name: tool.name,
                arguments: arguments,
                output: output
            )
        } else {
            event = PersistedChatToolEvent(
                kind: .call,
                name: tool.name,
                arguments: arguments
            )
            text = ChatToolTranscriptFormatter.toolCallText(
                name: tool.name,
                arguments: tool.arguments
            )
        }

        return AgentChatStreamingUpdate(
            itemID: sourceThreadID.map { "\($0):\(itemID)" } ?? itemID,
            text: text,
            isFinal: isFinal,
            toolEvent: event
        )
    }

    static func receiverThreadIDs(from item: [String: Any]) -> [String] {
        guard item["type"] as? String == "collabAgentToolCall" else { return [] }
        let receivers = (item["receiverThreadIds"] as? [Any] ?? []).compactMap(normalizedString)
        let stateThreadIDs = (item["agentsStates"] as? [String: Any]).map { Array($0.keys) } ?? []
        return Array(Set(receivers + stateThreadIDs)).sorted()
    }

    private static func commandExecutionTool(
        from item: [String: Any]
    ) -> (name: String, arguments: String, output: String?, failed: Bool, exitCode: String?) {
        let arguments = jsonString([
            "cmd": item["command"] as? String ?? "",
            "workdir": item["cwd"] as? String ?? "",
        ])
        let status = item["status"] as? String
        let exitCode = item["exitCode"] as? Int
        return (
            "exec_command",
            arguments,
            item["aggregatedOutput"] as? String,
            status == "failed" || (exitCode.map { $0 != 0 } ?? false),
            exitCode.map(String.init)
        )
    }

    private static func fileChangeTool(
        from item: [String: Any]
    ) -> (name: String, arguments: String, output: String?, failed: Bool, exitCode: String?) {
        let changes = item["changes"] as? [Any] ?? []
        let status = item["status"] as? String
        return (
            "file_change",
            jsonString(["changes": changes]),
            jsonString(["status": status ?? "completed", "changes": changes]),
            status == "failed",
            nil
        )
    }

    private static func mcpTool(
        from item: [String: Any]
    ) -> (name: String, arguments: String, output: String?, failed: Bool, exitCode: String?) {
        let server = normalizedString(item["server"])
        let name = [server, normalizedString(item["tool"])].compactMap { $0 }.joined(separator: ".")
        let status = item["status"] as? String
        let error = nonNullValue(item["error"])
        let outputValue = error ?? nonNullValue(item["result"])
        return (
            name.isEmpty ? "mcp_tool" : name,
            jsonString(item["arguments"]),
            outputValue.map(jsonString),
            status == "failed" || error != nil,
            nil
        )
    }

    private static func dynamicTool(
        from item: [String: Any]
    ) -> (name: String, arguments: String, output: String?, failed: Bool, exitCode: String?) {
        let namespace = normalizedString(item["namespace"])
        let name = [namespace, normalizedString(item["tool"])].compactMap { $0 }.joined(separator: ".")
        let status = item["status"] as? String
        return (
            name.isEmpty ? "dynamic_tool" : name,
            jsonString(item["arguments"]),
            nonNullValue(item["contentItems"]).map(jsonString),
            status == "failed" || item["success"] as? Bool == false,
            nil
        )
    }

    private static func collaborationTool(
        from item: [String: Any]
    ) -> (name: String, arguments: String, output: String?, failed: Bool, exitCode: String?) {
        let rawTool = item["tool"] as? String ?? "collaboration"
        let name = switch rawTool {
        case "spawnAgent": "spawn_agent"
        case "sendInput": "send_message"
        case "resumeAgent": "resume_agent"
        case "wait": "wait_agent"
        case "closeAgent": "close_agent"
        default: rawTool
        }
        var arguments: [String: Any] = [:]
        for key in ["prompt", "model", "reasoningEffort", "receiverThreadIds"] {
            if let value = item[key], !(value is NSNull) {
                arguments[key] = value
            }
        }
        let status = item["status"] as? String
        let output = jsonString([
            "status": status ?? "completed",
            "agents": item["agentsStates"] ?? [:],
        ])
        return (name, jsonString(arguments), output, status == "failed", nil)
    }

    private static func subagentActivityTool(
        from item: [String: Any]
    ) -> (name: String, arguments: String, output: String?, failed: Bool, exitCode: String?) {
        let fields: [String: Any] = [
            "agent": item["agentPath"] ?? "",
            "thread": item["agentThreadId"] ?? "",
            "activity": item["kind"] ?? "updated",
        ]
        return ("parallel_agent_activity", jsonString(fields), jsonString(fields), false, nil)
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonNullValue(_ value: Any?) -> Any? {
        guard let value, !(value is NSNull) else { return nil }
        return value
    }

    private static func argumentsByAddingSourceThreadID(_ threadID: String, to arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              var dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return arguments
        }
        dictionary["agentThreadId"] = threadID
        return jsonString(dictionary)
    }

    private static func jsonString(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }
}

nonisolated struct CodexAppServerLiveItemRouter {
    private var relatedThreadIDs: Set<String> = []
    private var bufferedUpdatesByThreadID: [String: [AgentChatStreamingUpdate]] = [:]

    mutating func route(
        _ update: AgentChatStreamingUpdate,
        eventThreadID: String,
        rootThreadID: String?,
        newlyRelatedThreadIDs: [String]
    ) -> [AgentChatStreamingUpdate] {
        let belongsToVisibleConversation = eventThreadID == rootThreadID
            || relatedThreadIDs.contains(eventThreadID)
        guard belongsToVisibleConversation else {
            if bufferedUpdatesByThreadID[eventThreadID] != nil || bufferedUpdatesByThreadID.count < 32 {
                var buffered = bufferedUpdatesByThreadID[eventThreadID] ?? []
                if buffered.count < 100 {
                    buffered.append(update)
                    bufferedUpdatesByThreadID[eventThreadID] = buffered
                }
            }
            return []
        }

        relatedThreadIDs.formUnion(newlyRelatedThreadIDs)
        let releasedUpdates = newlyRelatedThreadIDs.flatMap {
            bufferedUpdatesByThreadID.removeValue(forKey: $0) ?? []
        }
        return releasedUpdates + [update]
    }
}

nonisolated enum CodexAppServerPromptReplaySafety: Sendable, Equatable {
    case safeBeforeTurn
    case unsafeAfterTurnStarted
}

nonisolated struct CodexAppServerAttempt: Sendable, Equatable {
    let result: AgentChatExecutionResult
    let replaySafety: CodexAppServerPromptReplaySafety
}

nonisolated enum CodexAppServerFallbackPolicy {
    static func isFailure(_ result: AgentChatExecutionResult) -> Bool {
        let trimmed = result.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("Codex app-server failed:")
            || trimmed == "No response from Codex."
    }

    static func shouldFallbackToExec(_ attempt: CodexAppServerAttempt) -> Bool {
        isFailure(attempt.result) && attempt.replaySafety == .safeBeforeTurn
    }
}

public nonisolated struct AgentChatJSONLineBuffer: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)

        var lines: [String] = []
        var lineStart = buffer.startIndex
        while lineStart < buffer.endIndex,
              let newlineIndex = buffer[lineStart...].firstIndex(of: 0x0A) {
            lines.append(String(decoding: buffer[lineStart..<newlineIndex], as: UTF8.self))
            lineStart = buffer.index(after: newlineIndex)
        }

        if lineStart > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<lineStart)
        }
        return lines
    }

    public var remainingText: String {
        String(decoding: buffer, as: UTF8.self)
    }
}

public nonisolated final class AgentChatStreamingCoalescer: Sendable {
    private struct State: Sendable {
        var pendingTextByItemID: [String: String] = [:]
        var pendingItemIDs: [String] = []
        var pendingItemIDSet: Set<String> = []
        var deliveryScheduled = false
    }

    private let deliveryInterval: Duration
    private let onUpdate: @Sendable @MainActor (AgentChatStreamingUpdate) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(
        deliveryInterval: Duration = .milliseconds(67),
        onUpdate: @escaping @Sendable @MainActor (AgentChatStreamingUpdate) -> Void
    ) {
        self.deliveryInterval = deliveryInterval
        self.onUpdate = onUpdate
    }

    public func begin(itemID: String, initialText: String = "") {
        guard !initialText.isEmpty else { return }
        state.withLock { state in
            state.pendingTextByItemID[itemID, default: ""].append(initialText)
            markPending(itemID: itemID, state: &state)
            scheduleDeliveryIfNeeded(state: &state)
        }
    }

    public func append(delta: String, itemID: String) {
        guard !delta.isEmpty else { return }
        state.withLock { state in
            state.pendingTextByItemID[itemID, default: ""].append(delta)
            markPending(itemID: itemID, state: &state)
            scheduleDeliveryIfNeeded(state: &state)
        }
    }

    public func finish(itemID: String, finalText: String) {
        state.withLock { state in
            state.pendingTextByItemID.removeValue(forKey: itemID)
            state.pendingItemIDs.removeAll { $0 == itemID }
            state.pendingItemIDSet.remove(itemID)
            if !finalText.isEmpty {
                enqueue(AgentChatStreamingUpdate(
                    itemID: itemID,
                    text: finalText,
                    textKind: .replacement,
                    isFinal: true
                ))
            }
        }
    }

    public func flush() {
        deliverPendingUpdates()
    }

    private func markPending(itemID: String, state: inout State) {
        if state.pendingItemIDSet.insert(itemID).inserted {
            state.pendingItemIDs.append(itemID)
        }
    }

    private func scheduleDeliveryIfNeeded(state: inout State) {
        guard !state.deliveryScheduled else { return }
        state.deliveryScheduled = true
        Task.detached(priority: .userInitiated) { [deliveryInterval] in
            try? await Task.sleep(for: deliveryInterval)
            self.deliverPendingUpdates()
        }
    }

    private func deliverPendingUpdates() {
        state.withLock { state in
            let itemIDs = state.pendingItemIDs
            state.pendingItemIDs.removeAll(keepingCapacity: true)
            state.pendingItemIDSet.removeAll(keepingCapacity: true)
            state.deliveryScheduled = false

            for itemID in itemIDs {
                guard let text = state.pendingTextByItemID.removeValue(forKey: itemID) else { continue }
                enqueue(AgentChatStreamingUpdate(
                    itemID: itemID,
                    text: text,
                    textKind: .delta,
                    isFinal: false
                ))
            }
        }
    }

    private func enqueue(_ update: AgentChatStreamingUpdate) {
        DispatchQueue.main.async { [onUpdate] in
            onUpdate(update)
        }
    }
}

nonisolated struct CodexAppServerConnectionConfiguration: Equatable, Sendable {
    let workingDirectory: String
    let developerInstructions: String?
    let skipPermissions: Bool
    let sandboxEnabled: Bool
}

nonisolated final class CodexAppServerProcessHost {
    let process: Process
    let stdinPipe: Pipe
    let stdoutPipe: Pipe
    let stderrPipe: Pipe
    let configuration: CodexAppServerConnectionConfiguration
    var threadID: String?
    var isInUse: Bool
    var lastUsedAt: Date
    private let handlerLock = NSLock()
    private let requestIDLock = NSLock()
    private let stdoutBufferLock = NSLock()
    private var handlerGeneration = 0
    private var nextJSONRPCRequestID = 1
    private var stdoutBuffer = AgentChatJSONLineBuffer()

    init(
        process: Process,
        stdinPipe: Pipe,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        configuration: CodexAppServerConnectionConfiguration,
        threadID: String? = nil,
        isInUse: Bool = true,
        lastUsedAt: Date = Date()
    ) {
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.configuration = configuration
        self.threadID = threadID
        self.isInUse = isInUse
        self.lastUsedAt = lastUsedAt
    }

    func installReadabilityHandlers(
        discardBufferedStdout: Bool = false,
        onStdoutData: @escaping (Data) -> Void,
        onStderrData: @escaping (Data) -> Void
    ) {
        handlerLock.lock()
        if discardBufferedStdout {
            stdoutBufferLock.lock()
            stdoutBuffer = AgentChatJSONLineBuffer()
            stdoutBufferLock.unlock()
        }
        handlerGeneration += 1
        let generation = handlerGeneration
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            handlerLock.lock()
            guard generation == handlerGeneration else {
                handlerLock.unlock()
                return
            }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                onStdoutData(data)
            }
            handlerLock.unlock()
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            handlerLock.lock()
            guard generation == handlerGeneration else {
                handlerLock.unlock()
                return
            }
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                onStderrData(data)
            }
            handlerLock.unlock()
        }
        handlerLock.unlock()
    }

    func installIdleDrainers() {
        installReadabilityHandlers(
            onStdoutData: { [weak self] data in
                _ = self?.appendStdout(data)
            },
            onStderrData: { _ in }
        )
    }

    func stopReading() {
        handlerLock.lock()
        handlerGeneration += 1
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        handlerLock.unlock()
    }

    func appendStdout(_ data: Data) -> [String] {
        stdoutBufferLock.lock()
        defer { stdoutBufferLock.unlock() }
        return stdoutBuffer.append(data)
    }

    var remainingStdoutText: String {
        stdoutBufferLock.lock()
        defer { stdoutBufferLock.unlock() }
        return stdoutBuffer.remainingText
    }

    func allocateRequestID() -> Int {
        requestIDLock.lock()
        defer { requestIDLock.unlock() }
        let requestID = nextJSONRPCRequestID
        nextJSONRPCRequestID += 1
        return requestID
    }
}

nonisolated final class CodexAppServerProcessPool: @unchecked Sendable {
    // @unchecked Sendable: pool membership and lease metadata are serialized by `lock`;
    // a successfully acquired host is exclusively leased until `release`.
    private let lock = NSCondition()
    private var hostsByThreadID: [String: CodexAppServerProcessHost] = [:]
    private let maximumIdleHosts: Int

    init(maximumIdleHosts: Int = 6) {
        self.maximumIdleHosts = maximumIdleHosts
    }

    func acquire(
        threadID: String,
        configuration: CodexAppServerConnectionConfiguration,
        isCancelled: () -> Bool = { false }
    ) -> CodexAppServerProcessHost? {
        lock.lock()
        if isCancelled() {
            lock.unlock()
            return nil
        }
        while let host = hostsByThreadID[threadID], host.isInUse {
            if isCancelled() {
                lock.unlock()
                return nil
            }
            _ = lock.wait(until: Date().addingTimeInterval(0.25))
        }
        guard let host = hostsByThreadID[threadID] else {
            lock.unlock()
            return nil
        }
        guard host.process.isRunning else {
            hostsByThreadID.removeValue(forKey: threadID)
            lock.broadcast()
            lock.unlock()
            terminate([host])
            return nil
        }
        guard host.configuration == configuration else {
            hostsByThreadID.removeValue(forKey: threadID)
            lock.broadcast()
            lock.unlock()
            terminate([host])
            return nil
        }
        host.isInUse = true
        host.lastUsedAt = Date()
        lock.unlock()
        return host
    }

    @discardableResult
    func register(
        _ host: CodexAppServerProcessHost,
        threadID: String,
        isCancelled: () -> Bool = { false }
    ) -> Bool {
        var hostsToTerminate: [CodexAppServerProcessHost] = []
        lock.lock()
        if isCancelled() {
            lock.unlock()
            return false
        }
        while let existing = hostsByThreadID[threadID],
              existing !== host,
              existing.isInUse {
            if isCancelled() {
                lock.unlock()
                return false
            }
            _ = lock.wait(until: Date().addingTimeInterval(0.25))
        }
        if let replaced = hostsByThreadID.updateValue(host, forKey: threadID),
           replaced !== host,
           !replaced.isInUse {
            hostsToTerminate.append(replaced)
        }
        host.threadID = threadID
        hostsToTerminate.append(contentsOf: pruneIdleHostsIfNeeded(excluding: host))
        lock.broadcast()
        lock.unlock()
        terminate(hostsToTerminate)
        return true
    }

    func release(_ host: CodexAppServerProcessHost, keepAlive: Bool) {
        var hostsToTerminate: [CodexAppServerProcessHost] = []
        lock.lock()
        host.isInUse = false
        host.lastUsedAt = Date()
        let ownsRegisteredEntry = host.threadID.flatMap { hostsByThreadID[$0] } === host
        if !ownsRegisteredEntry || !keepAlive || !host.process.isRunning {
            if let threadID = host.threadID,
               hostsByThreadID[threadID] === host {
                hostsByThreadID.removeValue(forKey: threadID)
            }
            hostsToTerminate.append(host)
        } else {
            hostsToTerminate.append(contentsOf: pruneIdleHostsIfNeeded(excluding: host))
        }
        lock.broadcast()
        lock.unlock()
        terminate(hostsToTerminate)
    }

    private func pruneIdleHostsIfNeeded(
        excluding protectedHost: CodexAppServerProcessHost
    ) -> [CodexAppServerProcessHost] {
        let allIdleHosts = hostsByThreadID.values.filter { !$0.isInUse }
        let excessCount = max(0, allIdleHosts.count - maximumIdleHosts)
        guard excessCount > 0 else { return [] }

        let evictionCandidates = allIdleHosts
            .filter { $0 !== protectedHost }
            .sorted { $0.lastUsedAt < $1.lastUsedAt }
        let evicted = Array(evictionCandidates.prefix(excessCount))
        for host in evicted {
            if let threadID = host.threadID,
               hostsByThreadID[threadID] === host {
                hostsByThreadID.removeValue(forKey: threadID)
            }
        }
        return evicted
    }

    private func terminate(_ hosts: [CodexAppServerProcessHost]) {
        for host in hosts {
            host.installIdleDrainers()
            try? host.stdinPipe.fileHandleForWriting.close()
            if host.process.isRunning {
                host.process.terminate()
                host.process.waitUntilExit()
            }
            host.stopReading()
        }
    }
}

public nonisolated struct AgentChatAttachment: Sendable, Equatable {
    public nonisolated enum Kind: String, Sendable, Equatable {
        case file
        case image
        case video
    }

    public let path: String
    public let kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

public nonisolated struct CodexAppServerPermissionOverrides: Sendable, Equatable {
    public let approvalPolicy: String
    public let sandboxPolicyType: String

    public init(approvalPolicy: String, sandboxPolicyType: String) {
        self.approvalPolicy = approvalPolicy
        self.sandboxPolicyType = sandboxPolicyType
    }
}

public nonisolated enum AgentChatRuntime {
    private static let codexThreadReadyTimeout: TimeInterval = 20
    private static let codexTurnCompletionPollInterval: TimeInterval = 1
    private static let codexSteerAcknowledgementGracePeriod: TimeInterval = 2
    private static let codexAppServerProcessPool = CodexAppServerProcessPool()

    public nonisolated static func execute(
        agentType: AgentType,
        prompt: String,
        workingDirectory: String,
        conversationSessionID: String? = nil,
        claudeSystemPrompt: String? = nil,
        codexDeveloperInstructions: String? = nil,
        modelId: String? = nil,
        reasoningLevel: String? = nil,
        codexSkipPermissions: Bool = false,
        codexSandboxEnabled: Bool = false,
        attachments: [AgentChatAttachment] = [],
        codexSteerChannel: AgentChatSteerChannel? = nil,
        cancellationHandle: ShellExecutor.CancellationHandle? = nil,
        onStatusUpdate: (@Sendable @MainActor (AgentChatStatusUpdate) -> Void)? = nil,
        onStreamingUpdate: (@Sendable @MainActor (AgentChatStreamingUpdate) -> Void)? = nil
    ) async -> AgentChatExecutionResult {
        func finalized(_ result: AgentChatExecutionResult) -> AgentChatExecutionResult {
            let pendingSteerInputs = codexSteerChannel?.closeAndDrain() ?? []
            guard !pendingSteerInputs.isEmpty else { return result }
            var seenIDs = Set<UUID>()
            let combined = (result.deferredSteerInputs + pendingSteerInputs).filter {
                seenIDs.insert($0.id).inserted
            }
            return AgentChatExecutionResult(
                assistantText: result.assistantText,
                conversationSessionID: result.conversationSessionID,
                deferredSteerInputs: combined
            )
        }

        if Task.isCancelled {
            return finalized(AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            ))
        }

        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAttachmentList = normalizedAttachments(attachments)
        guard !normalizedPrompt.isEmpty || !normalizedAttachmentList.isEmpty else {
            return finalized(AgentChatExecutionResult(
                assistantText: "Prompt is empty.",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            ))
        }
        let promptWithAttachmentContext = promptWithAttachmentContext(
            basePrompt: normalizedPrompt,
            attachments: normalizedAttachmentList
        )
        var fallbackConversationSessionID = conversationSessionID

        if agentType == .codex {
            let appServerResult = await executeCodexViaAppServer(
                prompt: promptWithAttachmentContext,
                workingDirectory: workingDirectory,
                conversationSessionID: conversationSessionID,
                codexDeveloperInstructions: codexDeveloperInstructions,
                modelId: modelId,
                reasoningLevel: reasoningLevel,
                codexSkipPermissions: codexSkipPermissions,
                codexSandboxEnabled: codexSandboxEnabled,
                attachments: normalizedAttachmentList,
                steerChannel: codexSteerChannel,
                onStatusUpdate: onStatusUpdate,
                onStreamingUpdate: onStreamingUpdate
            )

            if shouldRetryCodexWithFreshThread(
                previousConversationSessionID: conversationSessionID,
                appServerText: appServerResult.result.assistantText
            ), appServerResult.replaySafety == .safeBeforeTurn {
                let freshThreadResult = await executeCodexViaAppServer(
                    prompt: promptWithAttachmentContext,
                    workingDirectory: workingDirectory,
                    conversationSessionID: nil,
                    codexDeveloperInstructions: codexDeveloperInstructions,
                    modelId: modelId,
                    reasoningLevel: reasoningLevel,
                    codexSkipPermissions: codexSkipPermissions,
                    codexSandboxEnabled: codexSandboxEnabled,
                    attachments: normalizedAttachmentList,
                    steerChannel: codexSteerChannel,
                    onStatusUpdate: onStatusUpdate,
                    onStreamingUpdate: onStreamingUpdate
                )
                if !CodexAppServerFallbackPolicy.isFailure(freshThreadResult.result) {
                    return finalized(freshThreadResult.result)
                }
                if !CodexAppServerFallbackPolicy.shouldFallbackToExec(freshThreadResult) {
                    return finalized(freshThreadResult.result)
                }
                // If resume metadata is stale, fallback execution should start a fresh
                // conversation instead of trying to resume the same broken thread ID.
                fallbackConversationSessionID = nil
            } else if !CodexAppServerFallbackPolicy.shouldFallbackToExec(appServerResult) {
                return finalized(appServerResult.result)
            }
        }

        guard let command = command(
            for: agentType,
            prompt: promptWithAttachmentContext,
            conversationSessionID: fallbackConversationSessionID,
            claudeSystemPrompt: claudeSystemPrompt,
            modelId: modelId,
            reasoningLevel: reasoningLevel,
            codexSkipPermissions: codexSkipPermissions,
            codexSandboxEnabled: codexSandboxEnabled,
            attachments: normalizedAttachmentList
        ) else {
            return finalized(AgentChatExecutionResult(
                assistantText: "Chat is not supported for \(agentType.displayName).",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            ))
        }

        let result = await ShellExecutor.executeCancellable(
            command,
            workingDirectory: workingDirectory,
            cancellationHandle: cancellationHandle
        )
        let parsed = parseOutput(for: agentType, stdout: result.stdout)
        let effectiveSessionID = parsed.conversationSessionID ?? normalizedSessionID(fallbackConversationSessionID)

        if Task.isCancelled {
            return finalized(AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: effectiveSessionID
            ))
        }

        if result.exitCode == 0 {
            let parsedText = parsed.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !parsedText.isEmpty {
                return finalized(AgentChatExecutionResult(
                    assistantText: parsedText,
                    conversationSessionID: effectiveSessionID
                ))
            }

            let fallbackText = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackText.isEmpty {
                return finalized(AgentChatExecutionResult(
                    assistantText: fallbackText,
                    conversationSessionID: effectiveSessionID
                ))
            }

            return finalized(AgentChatExecutionResult(
                assistantText: "No response from \(agentType.displayName).",
                conversationSessionID: effectiveSessionID
            ))
        }

        let details = conciseErrorDetails(stderr: result.stderr, stdout: result.stdout)
        let message: String
        if let details {
            message = "\(agentType.displayName) chat failed: \(details)"
        } else {
            message = "\(agentType.displayName) chat failed (exit \(result.exitCode))."
        }

        return finalized(AgentChatExecutionResult(
            assistantText: message,
            conversationSessionID: effectiveSessionID
        ))
    }

    private nonisolated final class ProcessCancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancellationRequested = false

        func setProcess(_ process: Process) {
            lock.lock()
            if cancellationRequested {
                if process.isRunning {
                    process.terminate()
                }
            } else {
                self.process = process
            }
            lock.unlock()
        }

        func clear() {
            lock.lock()
            process = nil
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancellationRequested
        }

        func cancel() {
            lock.lock()
            cancellationRequested = true
            if let process, process.isRunning {
                process.terminate()
            }
            lock.unlock()
        }
    }

    private nonisolated static func executeCodexViaAppServer(
        prompt: String,
        workingDirectory: String,
        conversationSessionID: String?,
        codexDeveloperInstructions: String?,
        modelId: String?,
        reasoningLevel: String?,
        codexSkipPermissions: Bool,
        codexSandboxEnabled: Bool,
        attachments: [AgentChatAttachment],
        steerChannel: AgentChatSteerChannel?,
        onStatusUpdate: (@Sendable @MainActor (AgentChatStatusUpdate) -> Void)?,
        onStreamingUpdate: (@Sendable @MainActor (AgentChatStreamingUpdate) -> Void)?
    ) async -> CodexAppServerAttempt {
        let cancellationBox = ProcessCancellationBox()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = executeCodexViaAppServerSync(
                        prompt: prompt,
                        workingDirectory: workingDirectory,
                        conversationSessionID: conversationSessionID,
                        codexDeveloperInstructions: codexDeveloperInstructions,
                        modelId: modelId,
                        reasoningLevel: reasoningLevel,
                        codexSkipPermissions: codexSkipPermissions,
                        codexSandboxEnabled: codexSandboxEnabled,
                        attachments: attachments,
                        steerChannel: steerChannel,
                        cancellationBox: cancellationBox,
                        onStatusUpdate: onStatusUpdate,
                        onStreamingUpdate: onStreamingUpdate
                    )
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            cancellationBox.cancel()
        }
    }

    private nonisolated static func executeCodexViaAppServerSync(
        prompt: String,
        workingDirectory: String,
        conversationSessionID: String?,
        codexDeveloperInstructions: String?,
        modelId: String?,
        reasoningLevel: String?,
        codexSkipPermissions: Bool,
        codexSandboxEnabled: Bool,
        attachments: [AgentChatAttachment],
        steerChannel: AgentChatSteerChannel?,
        cancellationBox: ProcessCancellationBox,
        onStatusUpdate: (@Sendable @MainActor (AgentChatStatusUpdate) -> Void)?,
        onStreamingUpdate: (@Sendable @MainActor (AgentChatStreamingUpdate) -> Void)?
    ) -> CodexAppServerAttempt {
        final class State {
            var stderrBuffer = Data()
            var threadID: String?
            var activeTurnID: String?
            var turnCompleted = false
            var turnStatus: String?
            var failure: String?
            var pendingSteerInputsByRequestID: [Int: AgentChatSteerInput] = [:]
            var assistantMessageOrder: [String] = []
            var assistantMessagesByID: [String: String] = [:]
            var liveItemRouter = CodexAppServerLiveItemRouter()
        }

        let connectionConfiguration = CodexAppServerConnectionConfiguration(
            workingDirectory: workingDirectory,
            developerInstructions: normalizedNonEmpty(codexDeveloperInstructions),
            skipPermissions: codexSkipPermissions,
            sandboxEnabled: codexSandboxEnabled
        )
        let resumedThreadID = normalizedSessionID(conversationSessionID)
        let reusedHost = resumedThreadID.flatMap {
            codexAppServerProcessPool.acquire(
                threadID: $0,
                configuration: connectionConfiguration,
                isCancelled: { cancellationBox.isCancelled }
            )
        }
        if cancellationBox.isCancelled {
            if let reusedHost {
                codexAppServerProcessPool.release(reusedHost, keepAlive: true)
            }
            return CodexAppServerAttempt(
                result: AgentChatExecutionResult(
                    assistantText: "Request cancelled.",
                    conversationSessionID: resumedThreadID
                ),
                replaySafety: .safeBeforeTurn
            )
        }
        if reusedHost == nil, let onStatusUpdate {
            DispatchQueue.main.async {
                onStatusUpdate(.startingCodex)
            }
        }
        let host: CodexAppServerProcessHost = reusedHost ?? {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            let codexFlagArgs = codexPermissionFlags(
                skipPermissions: codexSkipPermissions,
                sandboxEnabled: codexSandboxEnabled
            )
            let codexAppServerCommand = (
                ["command codex"] +
                codexFlagArgs +
                ["app-server", "--listen", "stdio://"]
            ).joined(separator: " ")
            process.arguments = ["-c", codexAppServerCommand]
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

            var environment = ProcessInfo.processInfo.environment
            if environment["PATH"] == nil {
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            }
            if environment["LANG"] == nil {
                environment["LANG"] = "C.UTF-8"
            }
            process.environment = environment

            let stdinPipe = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            return CodexAppServerProcessHost(
                process: process,
                stdinPipe: stdinPipe,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                configuration: connectionConfiguration
            )
        }()

        let state = State()
        state.threadID = reusedHost?.threadID
        let initializeRequestID = host.allocateRequestID()
        let threadRequestID = host.allocateRequestID()
        let turnRequestID = host.allocateRequestID()
        let streamingCoalescer = onStreamingUpdate.map {
            AgentChatStreamingCoalescer(onUpdate: $0)
        }
        let lock = NSLock()
        let threadReadySemaphore = DispatchSemaphore(value: 0)
        let turnCompletedSemaphore = DispatchSemaphore(value: 0)
        let steerResponseSemaphore = DispatchSemaphore(value: 0)

        let process = host.process
        let stdinPipe = host.stdinPipe
        let stdoutPipe = host.stdoutPipe
        let stderrPipe = host.stderrPipe
        var shouldKeepProcessAlive = false

        func sendJSON(_ payload: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let line = String(data: data, encoding: .utf8) else {
                return
            }
            let message = line + "\n"
            if let messageData = message.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(messageData)
            }
        }

        func parseResponseError(_ object: [String: Any]) -> String? {
            guard let error = object["error"] as? [String: Any] else { return nil }
            if let message = normalizedNonEmpty(error["message"] as? String) {
                return message
            }
            if let code = error["code"] as? Int {
                return "error code \(code)"
            }
            return "unknown JSON-RPC error"
        }

        func parseNotificationError(_ params: [String: Any]) -> String? {
            guard let error = params["error"] as? [String: Any] else { return nil }
            if let message = normalizedNonEmpty(error["message"] as? String) {
                return message
            }
            if let code = error["code"] as? Int {
                return "error code \(code)"
            }
            return "unknown error"
        }

        func mergedAssistantText(_ state: State) -> String {
            state.assistantMessageOrder
                .compactMap { state.assistantMessagesByID[$0] }
                .joined()
        }

        func routeLiveToolItem(_ item: [String: Any], params: [String: Any], isFinal: Bool) {
            guard let onStreamingUpdate,
                  let eventThreadID = normalizedNonEmpty(params["threadId"] as? String) else {
                return
            }

            lock.lock()
            let rootThreadID = state.threadID
            let sourceThreadID = eventThreadID == rootThreadID ? nil : eventThreadID
            guard let update = CodexAppServerLiveItemUpdate.update(
                for: item,
                isFinal: isFinal,
                sourceThreadID: sourceThreadID
            ) else {
                lock.unlock()
                return
            }
            let relatedThreadIDs = CodexAppServerLiveItemUpdate.receiverThreadIDs(from: item)
            let routedUpdates = state.liveItemRouter.route(
                update,
                eventThreadID: eventThreadID,
                rootThreadID: rootThreadID,
                newlyRelatedThreadIDs: relatedThreadIDs
            )
            lock.unlock()

            guard !routedUpdates.isEmpty else { return }

            streamingCoalescer?.flush()
            DispatchQueue.main.async {
                for routedUpdate in routedUpdates {
                    onStreamingUpdate(routedUpdate)
                }
            }
        }

        func handleJSONLine(_ line: String) {
            guard let object = parseJSONObject(line) else { return }

            if let method = object["method"] as? String,
               method.hasSuffix("/requestApproval") {
                let params = object["params"] as? [String: Any]
                let reason = normalizedNonEmpty(params?["reason"] as? String)
                    ?? "an operation requiring explicit approval"
                lock.lock()
                if state.failure == nil {
                    state.failure = "Blocked: Codex requested approval for \(reason). Chat tabs cannot approve yet."
                }
                state.turnCompleted = true
                state.turnStatus = "blocked"
                lock.unlock()

                if let requestID = object["id"] {
                    sendJSON([
                        "id": requestID,
                        "result": [
                            "decision": "decline",
                        ],
                    ])
                }
                threadReadySemaphore.signal()
                turnCompletedSemaphore.signal()
                return
            }

            if let id = object["id"] as? Int {
                lock.lock()
                let steerInput = state.pendingSteerInputsByRequestID[id]
                lock.unlock()

                if let error = parseResponseError(object) {
                    if let steerInput {
                        lock.lock()
                        state.pendingSteerInputsByRequestID.removeValue(forKey: id)
                        lock.unlock()
                        steerResponseSemaphore.signal()
                        return
                    }
                    lock.lock()
                    if state.failure == nil {
                        state.failure = error
                    }
                    lock.unlock()
                    threadReadySemaphore.signal()
                    turnCompletedSemaphore.signal()
                    return
                }

                if let steerInput {
                    steerChannel?.acknowledge(id: steerInput.id)
                    lock.lock()
                    state.pendingSteerInputsByRequestID.removeValue(forKey: id)
                    lock.unlock()
                    steerResponseSemaphore.signal()
                }
                if id == threadRequestID {
                    let threadID = ((object["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String
                    lock.lock()
                    state.threadID = normalizedSessionID(threadID)
                    lock.unlock()
                    threadReadySemaphore.signal()
                }
                return
            }

            guard let method = object["method"] as? String,
                  let params = object["params"] as? [String: Any] else {
                return
            }

            if let status = AgentChatStatusUpdate.codexAppServerNotification(method: method),
               let onStatusUpdate {
                DispatchQueue.main.async {
                    onStatusUpdate(status)
                }
            }

            switch method {
            case "error":
                let message = parseNotificationError(params) ?? "unknown error"
                lock.lock()
                if state.failure == nil {
                    state.failure = message
                }
                state.turnCompleted = true
                state.turnStatus = "failed"
                lock.unlock()
                threadReadySemaphore.signal()
                turnCompletedSemaphore.signal()
            case "turn/started":
                let turnID = ((params["turn"] as? [String: Any])?["id"] as? String)
                lock.lock()
                state.activeTurnID = normalizedNonEmpty(turnID)
                lock.unlock()
            case "item/started":
                guard let item = params["item"] as? [String: Any],
                      let itemType = item["type"] as? String else {
                    return
                }

                let eventThreadID = normalizedNonEmpty(params["threadId"] as? String)
                lock.lock()
                let rootThreadID = state.threadID
                lock.unlock()

                if itemType != "agentMessage" {
                    routeLiveToolItem(item, params: params, isFinal: false)
                    return
                }

                guard eventThreadID == rootThreadID,
                      let itemID = normalizedNonEmpty(item["id"] as? String) else {
                    return
                }

                lock.lock()
                if !state.assistantMessageOrder.contains(itemID) {
                    state.assistantMessageOrder.append(itemID)
                }
                if state.assistantMessagesByID[itemID] == nil {
                    state.assistantMessagesByID[itemID] = ""
                }
                let itemText = state.assistantMessagesByID[itemID] ?? ""
                lock.unlock()
                streamingCoalescer?.begin(itemID: itemID, initialText: itemText)
            case "item/agentMessage/delta":
                let eventThreadID = normalizedNonEmpty(params["threadId"] as? String)
                lock.lock()
                let rootThreadID = state.threadID
                lock.unlock()
                guard eventThreadID == rootThreadID,
                      let itemID = normalizedNonEmpty(params["itemId"] as? String),
                      let delta = params["delta"] as? String else {
                    return
                }

                lock.lock()
                if !state.assistantMessageOrder.contains(itemID) {
                    state.assistantMessageOrder.append(itemID)
                }
                state.assistantMessagesByID[itemID, default: ""].append(delta)
                lock.unlock()
                streamingCoalescer?.append(delta: delta, itemID: itemID)
            case "item/completed":
                guard let item = params["item"] as? [String: Any],
                      let itemType = item["type"] as? String else {
                    return
                }

                let eventThreadID = normalizedNonEmpty(params["threadId"] as? String)
                lock.lock()
                let rootThreadID = state.threadID
                lock.unlock()

                if itemType != "agentMessage" {
                    routeLiveToolItem(item, params: params, isFinal: true)
                    return
                }

                guard eventThreadID == rootThreadID,
                      let itemID = normalizedNonEmpty(item["id"] as? String) else {
                    return
                }

                let finalText = (item["text"] as? String) ?? ""
                lock.lock()
                if !state.assistantMessageOrder.contains(itemID) {
                    state.assistantMessageOrder.append(itemID)
                }
                state.assistantMessagesByID[itemID] = finalText
                lock.unlock()
                streamingCoalescer?.finish(itemID: itemID, finalText: finalText)
            case "turn/completed":
                let turn = params["turn"] as? [String: Any]
                let status = turn?["status"] as? String
                let failureMessage: String? = {
                    guard status == "failed",
                          let error = turn?["error"] as? [String: Any] else { return nil }
                    if let message = normalizedNonEmpty(error["message"] as? String) {
                        return message
                    }
                    if let code = error["code"] as? Int {
                        return "error code \(code)"
                    }
                    return "turn failed"
                }()
                lock.lock()
                state.turnCompleted = true
                state.turnStatus = status
                if state.failure == nil, let failureMessage {
                    state.failure = failureMessage
                }
                lock.unlock()
                turnCompletedSemaphore.signal()
            default:
                break
            }
        }

        host.installReadabilityHandlers(
            discardBufferedStdout: reusedHost != nil,
            onStdoutData: { data in
                let lines = host.appendStdout(data)
                for rawLine in lines {
                    let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        handleJSONLine(line)
                    }
                }
            },
            onStderrData: { data in
                lock.lock()
                state.stderrBuffer.append(data)
                lock.unlock()
            }
        )

        defer {
            cancellationBox.clear()
            if shouldKeepProcessAlive {
                host.installIdleDrainers()
            } else {
                host.stopReading()
            }
            codexAppServerProcessPool.release(host, keepAlive: shouldKeepProcessAlive)
        }

        if reusedHost == nil {
            do {
                try process.run()
                cancellationBox.setProcess(process)
            } catch {
                return CodexAppServerAttempt(
                    result: AgentChatExecutionResult(
                        assistantText: "Codex app-server failed: \(error.localizedDescription)",
                        conversationSessionID: resumedThreadID
                    ),
                    replaySafety: .safeBeforeTurn
                )
            }

            sendJSON([
                "id": initializeRequestID,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "magent",
                        "title": "Magent",
                        "version": "dev",
                    ],
                ],
            ])
            sendJSON([
                "method": "initialized",
                "params": [:],
            ])

            let threadRequestParams: [String: Any] = {
                var params: [String: Any] = [
                    "cwd": workingDirectory,
                ]
                if let developerInstructions = connectionConfiguration.developerInstructions {
                    // App-server steering for the whole thread (and subsequent turns).
                    params["developerInstructions"] = developerInstructions
                    params["baseInstructions"] = developerInstructions
                }
                if let resumedThreadID {
                    params["threadId"] = resumedThreadID
                }
                return params
            }()

            sendJSON([
                "id": threadRequestID,
                "method": resumedThreadID == nil ? "thread/start" : "thread/resume",
                "params": threadRequestParams,
            ])

            _ = threadReadySemaphore.wait(timeout: .now() + Self.codexThreadReadyTimeout)
        } else {
            cancellationBox.setProcess(process)
        }

        lock.lock()
        let resolvedThreadID = state.threadID
        let earlyFailure = state.failure
        lock.unlock()

        if Task.isCancelled {
            return CodexAppServerAttempt(
                result: AgentChatExecutionResult(
                    assistantText: "Request cancelled.",
                    conversationSessionID: resolvedThreadID ?? normalizedSessionID(conversationSessionID)
                ),
                replaySafety: .safeBeforeTurn
            )
        }

        guard let threadID = resolvedThreadID else {
            if let earlyFailure {
                return CodexAppServerAttempt(
                    result: AgentChatExecutionResult(
                        assistantText: "Codex app-server failed: \(earlyFailure)",
                        conversationSessionID: normalizedSessionID(conversationSessionID)
                    ),
                    replaySafety: .safeBeforeTurn
                )
            }
            return CodexAppServerAttempt(
                result: AgentChatExecutionResult(
                    assistantText: "Codex app-server failed: missing thread id",
                    conversationSessionID: normalizedSessionID(conversationSessionID)
                ),
                replaySafety: .safeBeforeTurn
            )
        }
        if reusedHost == nil {
            guard codexAppServerProcessPool.register(
                host,
                threadID: threadID,
                isCancelled: { cancellationBox.isCancelled }
            ) else {
                return CodexAppServerAttempt(
                    result: AgentChatExecutionResult(
                        assistantText: "Request cancelled.",
                        conversationSessionID: threadID
                    ),
                    replaySafety: .safeBeforeTurn
                )
            }
        }

        let inputItems = codexInputItems(prompt: prompt, attachments: attachments)
        var turnParams: [String: Any] = [
            "threadId": threadID,
            "input": inputItems,
            "cwd": workingDirectory,
        ]

        if let permissionOverrides = codexAppServerPermissionOverrides(
            skipPermissions: codexSkipPermissions,
            sandboxEnabled: codexSandboxEnabled
        ) {
            turnParams["approvalPolicy"] = permissionOverrides.approvalPolicy
            turnParams["sandboxPolicy"] = ["type": permissionOverrides.sandboxPolicyType]
        }

        if let modelID = normalizedNonEmpty(modelId) {
            turnParams["model"] = modelID
        }
        if let effort = normalizedNonEmpty(reasoningLevel) {
            turnParams["effort"] = effort
        }

        sendJSON([
            "id": turnRequestID,
            "method": "turn/start",
            "params": turnParams,
        ])

        func trySendSteerRequests() {
            while let steerInput = steerChannel?.popFirst() {
                lock.lock()
                let activeTurnID = state.activeTurnID
                let steerRequestID = host.allocateRequestID()
                if activeTurnID != nil {
                    state.pendingSteerInputsByRequestID[steerRequestID] = steerInput
                }
                lock.unlock()

                guard let activeTurnID else {
                    // Turn ID not ready yet; keep this steer prompt for the next cycle.
                    steerChannel?.prepend(steerInput)
                    break
                }
                sendJSON([
                    "id": steerRequestID,
                    "method": "turn/steer",
                    "params": [
                        "threadId": threadID,
                        "expectedTurnId": activeTurnID,
                        "input": codexInputItems(prompt: steerInput.text, attachments: []),
                    ],
                ])
            }
        }

        while true {
            trySendSteerRequests()
            if steerChannel?.waitForSubmission(timeout: .now()) == .success {
                continue
            }
            if turnCompletedSemaphore.wait(timeout: .now() + Self.codexTurnCompletionPollInterval) == .success {
                break
            }
            if Task.isCancelled { break }
            if !process.isRunning { break }
        }

        let steerAcknowledgementDeadline = Date().addingTimeInterval(
            Self.codexSteerAcknowledgementGracePeriod
        )
        while Date() < steerAcknowledgementDeadline {
            lock.lock()
            let hasPendingSteerResponses = !state.pendingSteerInputsByRequestID.isEmpty
            lock.unlock()
            guard hasPendingSteerResponses else { break }
            let remaining = max(0, steerAcknowledgementDeadline.timeIntervalSinceNow)
            _ = steerResponseSemaphore.wait(timeout: .now() + min(0.1, remaining))
        }

        lock.lock()
        state.pendingSteerInputsByRequestID.removeAll()
        lock.unlock()

        if Task.isCancelled {
            return CodexAppServerAttempt(
                result: AgentChatExecutionResult(
                    assistantText: "Request cancelled.",
                    conversationSessionID: threadID
                ),
                replaySafety: .unsafeAfterTurnStarted
            )
        }

        lock.lock()
        let stderr = String(data: state.stderrBuffer, encoding: .utf8) ?? ""
        let stdout = host.remainingStdoutText
        let failure = state.failure
        let turnCompletedSuccessfully = state.turnCompleted && state.turnStatus == "completed"
        let mergedAssistant = mergedAssistantText(state)
        lock.unlock()

        if let failure {
            return CodexAppServerAttempt(
                result: AgentChatExecutionResult(
                    assistantText: "Codex app-server failed: \(failure)",
                    conversationSessionID: threadID
                ),
                replaySafety: .unsafeAfterTurnStarted
            )
        }
        let finalText = mergedAssistant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalText.isEmpty {
            shouldKeepProcessAlive = turnCompletedSuccessfully && process.isRunning
            return CodexAppServerAttempt(
                result: AgentChatExecutionResult(
                    assistantText: finalText,
                    conversationSessionID: threadID
                ),
                replaySafety: .unsafeAfterTurnStarted
            )
        }

        if let details = conciseErrorDetails(stderr: stderr, stdout: stdout) {
            return CodexAppServerAttempt(
                result: AgentChatExecutionResult(
                    assistantText: "Codex app-server failed: \(details)",
                    conversationSessionID: threadID
                ),
                replaySafety: .unsafeAfterTurnStarted
            )
        }

        return CodexAppServerAttempt(
            result: AgentChatExecutionResult(
                assistantText: "No response from Codex.",
                conversationSessionID: threadID
            ),
            replaySafety: .unsafeAfterTurnStarted
        )
    }

    public nonisolated static func parseOutput(for agentType: AgentType, stdout: String) -> AgentChatExecutionResult {
        switch agentType {
        case .claude:
            return parseClaudeStreamJSON(stdout)
        case .codex:
            return parseCodexJSONL(stdout)
        case .custom:
            return AgentChatExecutionResult(assistantText: "", conversationSessionID: nil)
        }
    }

    public nonisolated static func parseClaudeStreamJSON(_ stdout: String) -> AgentChatExecutionResult {
        var sessionID: String?
        var resultText: String?
        var assistantMessageText: String?
        var deltaBuffer: [String] = []

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let json = parseJSONObject(line) else { continue }

            if let candidateSessionID = normalizedSessionID(json["session_id"] as? String) {
                sessionID = candidateSessionID
            }

            guard let type = json["type"] as? String else { continue }

            switch type {
            case "result":
                if let text = normalizedNonEmpty(json["result"] as? String) {
                    resultText = text
                }
            case "assistant":
                guard let message = json["message"] as? [String: Any],
                      let blocks = message["content"] as? [[String: Any]] else {
                    continue
                }

                let text = blocks.compactMap { block in
                    guard let blockType = block["type"] as? String,
                          blockType == "text" else {
                        return nil
                    }
                    return block["text"] as? String
                }.joined()

                if let normalized = normalizedNonEmpty(text) {
                    assistantMessageText = normalized
                }
            case "stream_event":
                guard let event = json["event"] as? [String: Any],
                      let eventType = event["type"] as? String,
                      eventType == "content_block_delta",
                      let delta = event["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String,
                      deltaType == "text_delta",
                      let text = delta["text"] as? String,
                      !text.isEmpty else {
                    continue
                }
                deltaBuffer.append(text)
            default:
                continue
            }
        }

        let mergedDeltas = normalizedNonEmpty(deltaBuffer.joined())
        return AgentChatExecutionResult(
            assistantText: resultText ?? assistantMessageText ?? mergedDeltas ?? "",
            conversationSessionID: sessionID
        )
    }

    public nonisolated static func parseCodexJSONL(_ stdout: String) -> AgentChatExecutionResult {
        var sessionID: String?
        var assistantText: String?

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let json = parseJSONObject(line),
                  let type = json["type"] as? String else {
                continue
            }

            if type == "thread.started",
               let candidate = normalizedSessionID(json["thread_id"] as? String) {
                sessionID = candidate
                continue
            }

            if type == "item.completed",
               let item = json["item"] as? [String: Any],
               let itemType = item["type"] as? String,
               itemType == "agent_message",
               let text = normalizedNonEmpty(item["text"] as? String) {
                assistantText = text
            }
        }

        return AgentChatExecutionResult(assistantText: assistantText ?? "", conversationSessionID: sessionID)
    }

    public nonisolated static func shouldRetryCodexWithFreshThread(
        previousConversationSessionID: String?,
        appServerText: String
    ) -> Bool {
        guard normalizedSessionID(previousConversationSessionID) != nil else { return false }
        let trimmed = appServerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("Codex app-server failed:") else { return false }

        let details = trimmed
            .replacingOccurrences(of: "Codex app-server failed:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !details.isEmpty else { return false }
        if details.contains("request approval") || details.contains("cannot approve yet") || details.contains("blocked:") {
            return false
        }

        let hasThreadContext = details.contains("thread")
            || details.contains("resume")
            || details.contains("conversation")
            || details.contains("not_found")
        let suggestsStaleSession = details.contains("not found")
            || details.contains("missing")
            || details.contains("unknown")
            || details.contains("invalid")
            || details.contains("closed")
            || details.contains("expired")
            || details.contains("archived")
            || details.contains("no such")
            || details.contains("404")
            || details.contains("does not exist")
        return hasThreadContext && suggestsStaleSession
    }

    private nonisolated static func command(
        for agentType: AgentType,
        prompt: String,
        conversationSessionID: String?,
        claudeSystemPrompt: String?,
        modelId: String?,
        reasoningLevel: String?,
        codexSkipPermissions: Bool,
        codexSandboxEnabled: Bool,
        attachments: [AgentChatAttachment]
    ) -> String? {
        let quotedPrompt = shellQuote(prompt)
        let normalizedConversationSessionID = normalizedSessionID(conversationSessionID)
        let normalizedModelID = normalizedNonEmpty(modelId)
        let normalizedReasoningLevel = normalizedNonEmpty(reasoningLevel)

        switch agentType {
        case .claude:
            let claudeBaseCommand: String
            if codexSkipPermissions {
                claudeBaseCommand = "command claude --dangerously-skip-permissions"
            } else if codexSandboxEnabled {
                claudeBaseCommand = "command claude --permission-mode auto"
            } else {
                claudeBaseCommand = "command claude"
            }
            var components: [String] = [
                claudeBaseCommand,
                "-p",
                quotedPrompt,
                "--output-format stream-json",
                "--verbose",
                "--include-partial-messages",
            ]

            if let normalizedModelID {
                components.append("--model \(shellQuote(normalizedModelID))")
            }
            if let normalizedReasoningLevel {
                components.append("--effort \(shellQuote(normalizedReasoningLevel))")
            }
            if let resumeID = normalizedConversationSessionID {
                components.append("--resume \(shellQuote(resumeID))")
            }

            if normalizedConversationSessionID == nil,
               let systemPrompt = normalizedNonEmpty(claudeSystemPrompt) {
                components.append("--append-system-prompt \(shellQuote(systemPrompt))")
            }

            return components.joined(separator: " ")
        case .codex:
            var components: [String] = ["command codex"]
            components.append(contentsOf: codexPermissionFlags(
                skipPermissions: codexSkipPermissions,
                sandboxEnabled: codexSandboxEnabled
            ))
            if let normalizedModelID {
                components.append("-m \(shellQuote(normalizedModelID))")
            }
            if let normalizedReasoningLevel {
                components.append("-c \(shellQuote("model_reasoning_effort=\"\(normalizedReasoningLevel)\""))")
            }
            let imageAttachmentFlags = attachments
                .filter { $0.kind == .image }
                .map { "--image \(shellQuote($0.path))" }
                .joined(separator: " ")
            let imageAttachmentSegment = imageAttachmentFlags.isEmpty ? "" : "\(imageAttachmentFlags) "
            if let resumeID = normalizedConversationSessionID {
                components.append("exec resume \(shellQuote(resumeID)) --json \(imageAttachmentSegment)\(quotedPrompt)")
            } else {
                components.append("exec --json \(imageAttachmentSegment)\(quotedPrompt)")
            }
            return components.joined(separator: " ")
        case .custom:
            return nil
        }
    }

    public nonisolated static func codexPermissionFlags(skipPermissions: Bool, sandboxEnabled: Bool) -> [String] {
        if skipPermissions {
            return ["--yolo"]
        }
        if sandboxEnabled {
            return ["--full-auto"]
        }
        return []
    }

    public nonisolated static func codexAppServerPermissionOverrides(
        skipPermissions: Bool,
        sandboxEnabled: Bool
    ) -> CodexAppServerPermissionOverrides? {
        if skipPermissions {
            return CodexAppServerPermissionOverrides(
                approvalPolicy: "never",
                sandboxPolicyType: "dangerFullAccess"
            )
        }
        if sandboxEnabled {
            return CodexAppServerPermissionOverrides(
                approvalPolicy: "never",
                sandboxPolicyType: "workspaceWrite"
            )
        }
        return nil
    }

    public nonisolated static func parseClaudeModelChange(from output: String) -> (modelLabel: String, effortLevel: String?)? {
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return lines.reversed().lazy.compactMap { parseClaudeModelChangeLine(String($0)) }.first
    }

    public nonisolated static func parseCodexModelChange(from output: String) -> (modelId: String, effortLevel: String?)? {
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return lines.reversed().lazy.compactMap { parseCodexModelChangeLine(String($0)) }.first
    }

    private nonisolated static func parseClaudeModelChangeLine(_ line: String) -> (modelLabel: String, effortLevel: String?)? {
        let stripped = line
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "⎿" || $0 == " " })

        guard stripped.hasPrefix("Set model to ") else { return nil }

        let remainder = String(stripped.dropFirst("Set model to ".count)).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        if let withRange = remainder.range(of: #" with (\w+) effort$"#, options: .regularExpression) {
            let modelLabel = String(remainder[remainder.startIndex..<withRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let withClause = String(remainder[withRange]).trimmingCharacters(in: .whitespaces)
            let effortWord = withClause
                .replacingOccurrences(of: "^with ", with: "", options: .regularExpression)
                .replacingOccurrences(of: " effort$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !modelLabel.isEmpty, !effortWord.isEmpty else { return nil }
            return (modelLabel, effortWord)
        }

        return (remainder, nil)
    }

    private nonisolated static func parseCodexModelChangeLine(_ line: String) -> (modelId: String, effortLevel: String?)? {
        let stripped = line
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "•" || $0 == " " })

        guard stripped.hasPrefix("Model changed to ") else { return nil }

        let remainder = String(stripped.dropFirst("Model changed to ".count)).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        let tokens = remainder.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let modelId = tokens.first, !modelId.isEmpty else { return nil }
        let effortLevel = tokens.count >= 2 ? tokens[1] : nil
        return (modelId, effortLevel)
    }

    private nonisolated static func parseJSONObject(_ line: Substring) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return nil
        }
        return json
    }

    private nonisolated static func parseJSONObject(_ line: String) -> [String: Any]? {
        parseJSONObject(Substring(line))
    }

    private nonisolated static func codexInputItems(
        prompt: String,
        attachments: [AgentChatAttachment]
    ) -> [[String: Any]] {
        var items: [[String: Any]] = []
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            items.append([
                "type": "text",
                "text": trimmedPrompt,
            ])
        }

        for attachment in attachments where attachment.kind == .image {
            items.append([
                "type": "local_image",
                "path": attachment.path,
            ])
        }

        if items.isEmpty {
            items.append([
                "type": "text",
                "text": "Read the attached files and respond.",
            ])
        }
        return items
    }

    private nonisolated static func normalizedAttachments(_ attachments: [AgentChatAttachment]) -> [AgentChatAttachment] {
        var seen: Set<String> = []
        var normalized: [AgentChatAttachment] = []

        for attachment in attachments {
            let trimmedPath = attachment.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else { continue }
            let normalizedPath = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: normalizedPath) else { continue }
            guard !seen.contains(normalizedPath) else { continue }
            seen.insert(normalizedPath)
            normalized.append(AgentChatAttachment(path: normalizedPath, kind: attachment.kind))
        }

        return normalized
    }

    private nonisolated static func promptWithAttachmentContext(
        basePrompt: String,
        attachments: [AgentChatAttachment]
    ) -> String {
        guard !attachments.isEmpty else { return basePrompt }

        let fileLines = attachments.map { attachment in
            let kindLabel: String
            switch attachment.kind {
            case .image:
                kindLabel = "image"
            case .video:
                kindLabel = "video"
            case .file:
                kindLabel = "file"
            }
            let fileURL = URL(fileURLWithPath: attachment.path).absoluteString
            return "- \(fileURL) (\(kindLabel), local path: \(attachment.path))"
        }
        let attachmentContext = "Attached files:\n" + fileLines.joined(separator: "\n")

        if basePrompt.isEmpty {
            return "Please review the attached files.\n\n\(attachmentContext)"
        }
        return "\(basePrompt)\n\n\(attachmentContext)"
    }

    private nonisolated static func conciseErrorDetails(stderr: String, stdout: String) -> String? {
        let candidates = [stderr, stdout]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let firstLine = trimmed
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !firstLine.isEmpty {
                return String(firstLine.prefix(400))
            }
            return String(trimmed.prefix(400))
        }
        return nil
    }

    private nonisolated static func normalizedSessionID(_ value: String?) -> String? {
        normalizedNonEmpty(value)
    }

    private nonisolated static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
