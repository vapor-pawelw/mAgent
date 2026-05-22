import Foundation
import MagentModels
import ShellInfra

public nonisolated struct AgentChatExecutionResult: Sendable, Equatable {
    public let assistantText: String
    public let conversationSessionID: String?

    public init(assistantText: String, conversationSessionID: String?) {
        self.assistantText = assistantText
        self.conversationSessionID = conversationSessionID
    }
}

public nonisolated struct AgentChatStreamingUpdate: Sendable, Equatable {
    public let itemID: String
    public let text: String
    public let isFinal: Bool

    public init(itemID: String, text: String, isFinal: Bool) {
        self.itemID = itemID
        self.text = text
        self.isFinal = isFinal
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

public nonisolated enum AgentChatRuntime {
    private static let codexThreadReadyTimeout: TimeInterval = 20
    private static let codexTurnCompletionPollInterval: TimeInterval = 1

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
        codexSteerStream: AsyncStream<String>? = nil,
        cancellationHandle: ShellExecutor.CancellationHandle? = nil,
        onStreamingUpdate: (@Sendable @MainActor (AgentChatStreamingUpdate) -> Void)? = nil
    ) async -> AgentChatExecutionResult {
        if Task.isCancelled {
            return AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            )
        }

        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAttachmentList = normalizedAttachments(attachments)
        guard !normalizedPrompt.isEmpty || !normalizedAttachmentList.isEmpty else {
            return AgentChatExecutionResult(assistantText: "Prompt is empty.", conversationSessionID: normalizedSessionID(conversationSessionID))
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
                steerStream: codexSteerStream,
                onStreamingUpdate: onStreamingUpdate
            )
            let trimmedAppServerText = appServerResult.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            let appServerFailed = trimmedAppServerText.hasPrefix("Codex app-server failed:")
                || trimmedAppServerText == "No response from Codex."

            if shouldRetryCodexWithFreshThread(
                previousConversationSessionID: conversationSessionID,
                appServerText: appServerResult.assistantText
            ) {
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
                    steerStream: codexSteerStream,
                    onStreamingUpdate: onStreamingUpdate
                )
                let trimmedFreshText = freshThreadResult.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                let freshFailed = trimmedFreshText.hasPrefix("Codex app-server failed:")
                    || trimmedFreshText == "No response from Codex."
                if !freshFailed {
                    return freshThreadResult
                }
                // If resume metadata is stale, fallback execution should start a fresh
                // conversation instead of trying to resume the same broken thread ID.
                fallbackConversationSessionID = nil
            }

            // Fall back to `codex exec --json` only when app-server failed for reasons
            // other than explicit cancellation.
            if !appServerFailed {
                return appServerResult
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
            return AgentChatExecutionResult(
                assistantText: "Chat is not supported for \(agentType.displayName).",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            )
        }

        let result = await ShellExecutor.executeCancellable(
            command,
            workingDirectory: workingDirectory,
            cancellationHandle: cancellationHandle
        )
        let parsed = parseOutput(for: agentType, stdout: result.stdout)
        let effectiveSessionID = parsed.conversationSessionID ?? normalizedSessionID(fallbackConversationSessionID)

        if Task.isCancelled {
            return AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: effectiveSessionID
            )
        }

        if result.exitCode == 0 {
            let parsedText = parsed.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !parsedText.isEmpty {
                return AgentChatExecutionResult(assistantText: parsedText, conversationSessionID: effectiveSessionID)
            }

            let fallbackText = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackText.isEmpty {
                return AgentChatExecutionResult(assistantText: fallbackText, conversationSessionID: effectiveSessionID)
            }

            return AgentChatExecutionResult(
                assistantText: "No response from \(agentType.displayName).",
                conversationSessionID: effectiveSessionID
            )
        }

        let details = conciseErrorDetails(stderr: result.stderr, stdout: result.stdout)
        let message: String
        if let details {
            message = "\(agentType.displayName) chat failed: \(details)"
        } else {
            message = "\(agentType.displayName) chat failed (exit \(result.exitCode))."
        }

        return AgentChatExecutionResult(assistantText: message, conversationSessionID: effectiveSessionID)
    }

    private nonisolated final class ProcessCancellationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func setProcess(_ process: Process) {
            lock.lock()
            self.process = process
            lock.unlock()
        }

        func clear() {
            lock.lock()
            process = nil
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let process = process
            lock.unlock()
            guard let process, process.isRunning else { return }
            process.terminate()
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
        steerStream: AsyncStream<String>?,
        onStreamingUpdate: (@Sendable @MainActor (AgentChatStreamingUpdate) -> Void)?
    ) async -> AgentChatExecutionResult {
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
                        steerStream: steerStream,
                        cancellationBox: cancellationBox,
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
        steerStream: AsyncStream<String>?,
        cancellationBox: ProcessCancellationBox,
        onStreamingUpdate: (@Sendable @MainActor (AgentChatStreamingUpdate) -> Void)?
    ) -> AgentChatExecutionResult {
        final class State {
            var stdoutBuffer = Data()
            var stderrBuffer = Data()
            var threadID: String?
            var activeTurnID: String?
            var turnCompleted = false
            var turnStatus: String?
            var failure: String?
            var pendingSteerRequestIDs: Set<Int> = []
            var nextSteerRequestID: Int = 1_000_000
            var assistantMessageOrder: [String] = []
            var assistantMessagesByID: [String: String] = [:]
        }

        let state = State()
        let lock = NSLock()
        let threadReadySemaphore = DispatchSemaphore(value: 0)
        let turnCompletedSemaphore = DispatchSemaphore(value: 0)
        let steerDrainSemaphore = DispatchSemaphore(value: 0)
        final class SteerQueue {
            private let lock = NSLock()
            private var values: [String] = []

            func append(_ value: String) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                lock.lock()
                values.append(trimmed)
                lock.unlock()
            }

            func popFirst() -> String? {
                lock.lock()
                defer { lock.unlock() }
                guard !values.isEmpty else { return nil }
                return values.removeFirst()
            }
        }
        let steerQueue = SteerQueue()
        let steerPumpTask: Task<Void, Never>?
        if let steerStream {
            steerPumpTask = Task.detached(priority: .userInitiated) {
                for await steerText in steerStream {
                    steerQueue.append(steerText)
                    steerDrainSemaphore.signal()
                }
            }
        } else {
            steerPumpTask = nil
        }

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
                let isSteerResponse = state.pendingSteerRequestIDs.contains(id)
                if isSteerResponse {
                    state.pendingSteerRequestIDs.remove(id)
                }
                lock.unlock()

                if let error = parseResponseError(object) {
                    if isSteerResponse {
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

                if id == 2 {
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
                      let itemType = item["type"] as? String,
                      itemType == "agentMessage",
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
                if !itemText.isEmpty {
                    Task { @MainActor in
                        onStreamingUpdate?(AgentChatStreamingUpdate(
                            itemID: itemID,
                            text: itemText,
                            isFinal: false
                        ))
                    }
                }
            case "item/agentMessage/delta":
                guard let itemID = normalizedNonEmpty(params["itemId"] as? String),
                      let delta = params["delta"] as? String else {
                    return
                }

                lock.lock()
                if !state.assistantMessageOrder.contains(itemID) {
                    state.assistantMessageOrder.append(itemID)
                }
                state.assistantMessagesByID[itemID, default: ""].append(delta)
                let itemText = state.assistantMessagesByID[itemID] ?? ""
                lock.unlock()
                if !itemText.isEmpty {
                    Task { @MainActor in
                        onStreamingUpdate?(AgentChatStreamingUpdate(
                            itemID: itemID,
                            text: itemText,
                            isFinal: false
                        ))
                    }
                }
            case "item/completed":
                guard let item = params["item"] as? [String: Any],
                      let itemType = item["type"] as? String,
                      itemType == "agentMessage",
                      let itemID = normalizedNonEmpty(item["id"] as? String) else {
                    return
                }

                let finalText = (item["text"] as? String) ?? ""
                lock.lock()
                if !state.assistantMessageOrder.contains(itemID) {
                    state.assistantMessageOrder.append(itemID)
                }
                state.assistantMessagesByID[itemID] = finalText
                let itemText = state.assistantMessagesByID[itemID] ?? ""
                lock.unlock()
                if !itemText.isEmpty {
                    Task { @MainActor in
                        onStreamingUpdate?(AgentChatStreamingUpdate(
                            itemID: itemID,
                            text: itemText,
                            isFinal: true
                        ))
                    }
                }
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

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }

            lock.lock()
            state.stdoutBuffer.append(data)

            while let newlineRange = state.stdoutBuffer.firstRange(of: Data([0x0A])) {
                let lineData = state.stdoutBuffer.subdata(in: state.stdoutBuffer.startIndex..<newlineRange.lowerBound)
                state.stdoutBuffer.removeSubrange(state.stdoutBuffer.startIndex...newlineRange.lowerBound)
                if let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !line.isEmpty {
                    lock.unlock()
                    handleJSONLine(line)
                    lock.lock()
                }
            }
            lock.unlock()
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            lock.lock()
            state.stderrBuffer.append(data)
            lock.unlock()
        }

        defer {
            steerPumpTask?.cancel()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            cancellationBox.clear()
            if process.isRunning {
                process.terminate()
            }
        }

        do {
            try process.run()
            cancellationBox.setProcess(process)
        } catch {
            return AgentChatExecutionResult(
                assistantText: "Codex app-server failed: \(error.localizedDescription)",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            )
        }

        sendJSON([
            "id": 1,
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
            if let developerInstructions = normalizedNonEmpty(codexDeveloperInstructions) {
                // App-server steering for the whole thread (and subsequent turns).
                params["developerInstructions"] = developerInstructions
                params["baseInstructions"] = developerInstructions
            }
            if let threadID = normalizedSessionID(conversationSessionID) {
                params["threadId"] = threadID
            }
            return params
        }()

        sendJSON([
            "id": 2,
            "method": normalizedSessionID(conversationSessionID) == nil ? "thread/start" : "thread/resume",
            "params": threadRequestParams,
        ])

        _ = threadReadySemaphore.wait(timeout: .now() + Self.codexThreadReadyTimeout)

        lock.lock()
        let resolvedThreadID = state.threadID
        let earlyFailure = state.failure
        lock.unlock()

        if Task.isCancelled {
            return AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: resolvedThreadID ?? normalizedSessionID(conversationSessionID)
            )
        }

        guard let threadID = resolvedThreadID else {
            if let earlyFailure {
                return AgentChatExecutionResult(
                    assistantText: "Codex app-server failed: \(earlyFailure)",
                    conversationSessionID: normalizedSessionID(conversationSessionID)
                )
            }
            return AgentChatExecutionResult(
                assistantText: "Codex app-server failed: missing thread id",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            )
        }

        let inputItems = codexInputItems(prompt: prompt, attachments: attachments)
        var turnParams: [String: Any] = [
            "threadId": threadID,
            "input": inputItems,
            "cwd": workingDirectory,
        ]

        if let modelID = normalizedNonEmpty(modelId) {
            turnParams["model"] = modelID
        }
        if let effort = normalizedNonEmpty(reasoningLevel) {
            turnParams["effort"] = effort
        }

        sendJSON([
            "id": 3,
            "method": "turn/start",
            "params": turnParams,
        ])

        func trySendSteerRequests() {
            while let steerText = steerQueue.popFirst() {
                lock.lock()
                let activeTurnID = state.activeTurnID
                let nextSteerRequestID = state.nextSteerRequestID
                if activeTurnID != nil {
                    state.nextSteerRequestID += 1
                    state.pendingSteerRequestIDs.insert(nextSteerRequestID)
                }
                lock.unlock()

                guard let activeTurnID else {
                    // Turn ID not ready yet; keep this steer prompt for the next cycle.
                    steerQueue.append(steerText)
                    break
                }
                sendJSON([
                    "id": nextSteerRequestID,
                    "method": "turn/steer",
                    "params": [
                        "threadId": threadID,
                        "expectedTurnId": activeTurnID,
                        "input": codexInputItems(prompt: steerText, attachments: []),
                    ],
                ])
            }
        }

        while true {
            trySendSteerRequests()
            if steerDrainSemaphore.wait(timeout: .now()) == .success {
                continue
            }
            if turnCompletedSemaphore.wait(timeout: .now() + Self.codexTurnCompletionPollInterval) == .success {
                break
            }
            if Task.isCancelled { break }
            if !process.isRunning { break }
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        if Task.isCancelled {
            return AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: threadID
            )
        }

        lock.lock()
        let stderr = String(data: state.stderrBuffer, encoding: .utf8) ?? ""
        let stdout = String(data: state.stdoutBuffer, encoding: .utf8) ?? ""
        let failure = state.failure
        let mergedAssistant = mergedAssistantText(state)
        lock.unlock()

        if let failure {
            return AgentChatExecutionResult(
                assistantText: "Codex app-server failed: \(failure)",
                conversationSessionID: threadID
            )
        }
        let finalText = mergedAssistant.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalText.isEmpty {
            return AgentChatExecutionResult(
                assistantText: finalText,
                conversationSessionID: threadID
            )
        }

        if let details = conciseErrorDetails(stderr: stderr, stdout: stdout) {
            return AgentChatExecutionResult(
                assistantText: "Codex app-server failed: \(details)",
                conversationSessionID: threadID
            )
        }

        return AgentChatExecutionResult(
            assistantText: "No response from Codex.",
            conversationSessionID: threadID
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
