import Foundation
import MagentCore

private struct IPCAgentSelection {
    let agentType: AgentType?
    let surface: AgentSurface?
    let useAgentCommand: Bool
}

private struct IPCAgentSelectionError: Error, CustomStringConvertible {
    let description: String
}

private func parseIPCAgentSelection(
    _ rawValue: String?,
    chatsEnabled: Bool
) -> Result<IPCAgentSelection, IPCAgentSelectionError> {
    guard let rawValue, !rawValue.isEmpty else {
        return .success(IPCAgentSelection(agentType: nil, surface: nil, useAgentCommand: true))
    }

    let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
    let agentRaw = parts[0]
    let surface = parts.count == 2 ? AgentSurface(rawValue: parts[1]) : nil
    if parts.count == 2, surface == nil {
        return .failure(IPCAgentSelectionError(description: "Unknown agent surface: \(parts[1]). Valid surfaces: terminal, chat"))
    }

    if agentRaw == "terminal" {
        if surface == .chat {
            return .failure(IPCAgentSelectionError(description: "Terminal does not support the chat surface"))
        }
        return .success(IPCAgentSelection(agentType: nil, surface: .terminal, useAgentCommand: false))
    }

    guard let agentType = AgentType(rawValue: agentRaw) else {
        return .failure(IPCAgentSelectionError(description: "Unknown agent type: \(agentRaw). Valid: claude, codex, custom, terminal"))
    }

    let selectedSurface = surface ?? agentType.defaultSurface
    guard agentType.supportedSurfaces(chatsEnabled: chatsEnabled).contains(selectedSurface) else {
        return .failure(IPCAgentSelectionError(description: "Agent type \(agentType.rawValue) does not support the \(selectedSurface.rawValue) surface"))
    }

    return .success(IPCAgentSelection(
        agentType: agentType,
        surface: selectedSurface,
        useAgentCommand: selectedSurface == .terminal
    ))
}

private actor IPCChatPromptCoordinator {
    enum SubmissionAction {
        case start(steerStream: AsyncStream<String>?)
        case steered
        case busy
    }

    private enum InFlightRequest {
        case codex(continuation: AsyncStream<String>.Continuation)
        case nonSteerable
    }

    private var requestsByKey: [String: InFlightRequest] = [:]

    func prepareSubmission(key: String, agentType: AgentType, prompt: String) -> SubmissionAction {
        if let existing = requestsByKey[key] {
            switch existing {
            case .codex(let continuation):
                if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return .busy
                }
                continuation.yield(prompt)
                return .steered
            case .nonSteerable:
                return .busy
            }
        }

        guard agentType == .codex else {
            requestsByKey[key] = .nonSteerable
            return .start(steerStream: nil)
        }

        var capturedContinuation: AsyncStream<String>.Continuation?
        let steerStream = AsyncStream<String> { continuation in
            capturedContinuation = continuation
        }
        guard let continuation = capturedContinuation else {
            requestsByKey[key] = .nonSteerable
            return .start(steerStream: nil)
        }
        requestsByKey[key] = .codex(continuation: continuation)
        return .start(steerStream: steerStream)
    }

    func finishRequest(key: String) {
        guard let request = requestsByKey.removeValue(forKey: key) else { return }
        if case .codex(let continuation) = request {
            continuation.finish()
        }
    }
}

final class IPCCommandHandler {

    static let shared = IPCCommandHandler()

    let persistence = PersistenceService.shared
    let threadManager = ThreadManager.shared
    let tmux = TmuxService.shared
    private let chatPromptCoordinator = IPCChatPromptCoordinator()

    func handle(_ request: IPCRequest) async -> IPCResponse {
        switch request.command {
        case "create-thread":
            return await createThread(request)
        case "batch-create":
            return await batchCreateThreads(request)
        case "list-projects":
            return listProjects(request)
        case "list-threads":
            return listThreads(request)
        case "list-archived":
            return listArchived(request)
        case "send-prompt":
            return await sendPrompt(request)
        case "start-agent":
            return await startAgent(request)
        case "archive-thread":
            return await archiveThread(request)
        case "delete-thread":
            return await deleteThread(request)
        case "list-tabs":
            return listTabs(request)
        case "read-tab":
            return await readTab(request)
        case "create-tab":
            return await createTab(request)
        case "create-web-tab":
            return await createWebTab(request)
        case "close-tab":
            return await closeTab(request)
        case "rename-tab":
            return await renameTab(request)
        case "pin-tab":
            return setTabPinned(request, pinned: request.remove != true)
        case "unpin-tab":
            return setTabPinned(request, pinned: false)
        case "auto-rename-thread", "rename-thread":
            return await autoRenameThread(request)
        case "rename-branch", "rename-thread-exact":
            return await renameBranch(request)
        case "set-description":
            return setDescription(request)
        case "set-priority":
            return setPriority(request)
        case "set-thread-icon":
            return setThreadIcon(request)
        case "set-base-branch":
            return setBaseBranch(request)
        case "hide-thread":
            return setThreadHidden(request, hidden: true)
        case "unhide-thread":
            return setThreadHidden(request, hidden: false)
        case "favorite-thread":
            return setThreadFavorite(request, favorite: true)
        case "unfavorite-thread":
            return setThreadFavorite(request, favorite: false)
        case "current-thread":
            return currentThread(request)
        case "thread-info":
            return threadInfo(request)
        case "list-sections":
            return handleListSections(request)
        case "add-section":
            return handleAddSection(request)
        case "remove-section":
            return handleRemoveSection(request)
        case "reorder-section":
            return handleReorderSection(request)
        case "rename-section":
            return handleRenameSection(request)
        case "hide-section":
            return handleHideSection(request)
        case "show-section":
            return handleShowSection(request)
        case "keep-alive-thread":
            return setThreadKeepAlive(request, enabled: request.remove != true)
        case "keep-alive-tab":
            return setTabKeepAlive(request, enabled: request.remove != true)
        case "keep-alive-section":
            return setSectionKeepAlive(request, enabled: request.remove != true)
        case "move-thread":
            return await handleMoveThread(request)
        default:
            return .failure("Unknown command: \(request.command)", id: request.id)
        }
    }

    // MARK: - Thread Resolution

    enum ResolveResult {
        case found(MagentThread)
        case error(IPCResponse)
    }

    func resolveThread(_ request: IPCRequest) -> ResolveResult {
        if let threadId = request.threadId, let uuid = UUID(uuidString: threadId) {
            if let thread = threadManager.threads.first(where: { $0.id == uuid }) {
                return .found(thread)
            }
            return .error(.failure("Thread not found: \(threadId)", id: request.id))
        }
        if let threadName = request.threadName {
            if let thread = threadManager.threads.first(where: {
                $0.name.caseInsensitiveCompare(threadName) == .orderedSame
            }) {
                return .found(thread)
            }
            return .error(.failure("Thread not found: \(threadName)", id: request.id))
        }
        return .error(.failure("Missing required field: threadId or threadName", id: request.id))
    }

    // MARK: - From-Thread Resolution

    /// Resolves the "from-thread" context: inherits base branch and section from a source thread.
    /// `fromThreadId` is auto-injected by the CLI from `$MAGENT_THREAD_ID`; `fromThreadName`
    /// is set explicitly via `--from-thread`. Special name values: `"none"` suppresses
    /// auto-detection, `"main"` resolves to the project's main worktree thread.
    enum FromThreadResult {
        case none
        case resolved(MagentThread)
        case error(IPCResponse)
    }

    func resolveFromThread(
        fromThreadId: String?,
        fromThreadName: String?,
        project: Project,
        requestId: String?
    ) -> FromThreadResult {
        // Explicit name takes precedence over auto-injected ID
        if let name = fromThreadName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            if name.caseInsensitiveCompare("none") == .orderedSame {
                return .none
            }
            if name.caseInsensitiveCompare("main") == .orderedSame {
                if let mainThread = threadManager.threads.first(where: {
                    $0.projectId == project.id && $0.isMain
                }) {
                    return .resolved(mainThread)
                }
                return .error(.failure("Main thread not found for project: \(project.name)", id: requestId))
            }
            if let thread = threadManager.threads.first(where: {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
            }) {
                guard thread.projectId == project.id else {
                    return .error(.failure("From-thread '\(name)' belongs to a different project", id: requestId))
                }
                return .resolved(thread)
            }
            return .error(.failure("From-thread not found: \(name)", id: requestId))
        }

        // Fall back to auto-injected thread ID
        if let idStr = fromThreadId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !idStr.isEmpty,
           let uuid = UUID(uuidString: idStr) {
            if let thread = threadManager.threads.first(where: { $0.id == uuid }) {
                guard thread.projectId == project.id else {
                    // Auto-injected ID from a different project — silently ignore
                    return .none
                }
                return .resolved(thread)
            }
            // Auto-injected ID not found — not an error, just ignore
            return .none
        }

        return .none
    }

    /// Extracts the branch from a source thread, using the same resolution cascade as `--base-thread`.
    func branchFromThread(_ thread: MagentThread, project: Project) -> String? {
        if let actualBranch = thread.actualBranch?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !actualBranch.isEmpty,
           actualBranch != "HEAD" {
            return actualBranch
        }
        let explicitBranch = thread.branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitBranch.isEmpty {
            return explicitBranch
        }
        if let expected = threadManager.resolveExpectedBranch(for: thread)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !expected.isEmpty {
            return expected
        }
        return nil
    }

    // MARK: - Description Length Warnings (CLI only)

    private static let preferredTaskDescriptionMinWords = 2
    private static let preferredTaskDescriptionMaxWords = 8

    private func taskDescriptionWordCountForWarning(_ rawDescription: String) -> Int {
        let trimmed = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let effectiveDescription: String
        if trimmed.hasPrefix(ThreadManager.draftDescriptionPrefix) {
            effectiveDescription = String(trimmed.dropFirst(ThreadManager.draftDescriptionPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            effectiveDescription = trimmed
        }

        return effectiveDescription.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func descriptionPreferenceWarning(_ description: String) -> String? {
        let count = taskDescriptionWordCountForWarning(description)
        guard count > Self.preferredTaskDescriptionMaxWords else { return nil }
        return "Task description has \(count) words; preferred length is \(Self.preferredTaskDescriptionMinWords)-\(Self.preferredTaskDescriptionMaxWords) words."
    }

    private func requestedTabName(from request: IPCRequest) -> String? {
        if let name = request.newName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return nil
    }

    // MARK: - Commands

    private func createThread(_ request: IPCRequest) async -> IPCResponse {
        guard let projectName = request.project else {
            return .failure("Missing required field: project", id: request.id)
        }

        let settings = persistence.loadSettings()
        guard let project = settings.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .failure("Project not found: \(projectName)", id: request.id)
        }

        let selection: IPCAgentSelection
        switch parseIPCAgentSelection(request.agentType, chatsEnabled: settings.isChatsFeatureEnabled) {
        case .success(let parsed):
            selection = parsed
        case .failure(let message):
            return .failure(message.description, id: request.id)
        }
        let requestedAgent = selection.agentType
        let useAgentCommand = selection.useAgentCommand
        if let requestedAgent, !settings.availableActiveAgents.contains(requestedAgent) {
            return .failure("Agent type is not enabled: \(requestedAgent.rawValue)", id: request.id)
        }

        // Resolve requested name: --name takes precedence, --description generates a slug
        let requestedName: String?
        if let exactName = request.newName, !exactName.isEmpty {
            requestedName = exactName
        } else if let description = request.description, !description.isEmpty {
            let resolvedAgent = requestedAgent ?? threadManager.resolveAgentType(
                for: project.id, requestedAgentType: nil, settings: settings
            )
            let renameResult = await threadManager.autoRenameCandidates(
                from: description, agentType: resolvedAgent, projectId: project.id
            )
            if case .candidates(let slugs) = renameResult {
                requestedName = slugs.first
            } else {
                requestedName = nil
            }
        } else {
            requestedName = nil
        }

        // Resolve from-thread context (auto-injected from $MAGENT_THREAD_ID or explicit --from-thread)
        let fromThread: MagentThread?
        switch resolveFromThread(
            fromThreadId: request.fromThreadId,
            fromThreadName: request.fromThreadName,
            project: project,
            requestId: request.id
        ) {
        case .none: fromThread = nil
        case .resolved(let t): fromThread = t
        case .error(let err): return err
        }

        // Resolve optional base branch (explicit branch or from an existing thread)
        let normalizedBaseThreadName = request.baseThreadName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBaseBranch = request.baseBranch?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedBaseThreadName, !normalizedBaseThreadName.isEmpty,
           let normalizedBaseBranch, !normalizedBaseBranch.isEmpty {
            return .failure("Use either baseThreadName or baseBranch, not both", id: request.id)
        }

        let hasExplicitBase = (normalizedBaseThreadName != nil && !normalizedBaseThreadName!.isEmpty) ||
            (normalizedBaseBranch != nil && !normalizedBaseBranch!.isEmpty)

        let requestedBaseBranch: String?
        if let normalizedBaseBranch, !normalizedBaseBranch.isEmpty {
            requestedBaseBranch = normalizedBaseBranch
        } else if let normalizedBaseThreadName, !normalizedBaseThreadName.isEmpty {
            guard let baseThread = threadManager.threads.first(where: {
                $0.name.caseInsensitiveCompare(normalizedBaseThreadName) == .orderedSame
            }) else {
                return .failure("Base thread not found: \(normalizedBaseThreadName)", id: request.id)
            }
            guard baseThread.projectId == project.id else {
                return .failure("Base thread '\(normalizedBaseThreadName)' belongs to a different project", id: request.id)
            }

            if let actualBranch = baseThread.actualBranch?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                      !actualBranch.isEmpty,
                      actualBranch != "HEAD" {
                requestedBaseBranch = actualBranch
            } else {
                let explicitThreadBranch = baseThread.branchName
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !explicitThreadBranch.isEmpty {
                    requestedBaseBranch = explicitThreadBranch
                } else if let expectedBranch = threadManager.resolveExpectedBranch(for: baseThread)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                          !expectedBranch.isEmpty {
                    requestedBaseBranch = expectedBranch
                } else if let projectDefault = project.defaultBranch?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                          !projectDefault.isEmpty {
                    requestedBaseBranch = projectDefault
                } else {
                    return .failure("Could not determine base branch from thread: \(normalizedBaseThreadName)", id: request.id)
                }
            }
        } else if !hasExplicitBase, let fromThread, let inheritedBranch = branchFromThread(fromThread, project: project) {
            // Inherit base branch from from-thread when no explicit base was provided
            requestedBaseBranch = inheritedBranch
        } else {
            requestedBaseBranch = nil
        }

        // Resolve requested section
        let hasExplicitSection = request.sectionName != nil && !request.sectionName!.isEmpty
        let requestedSectionId: UUID?
        if let sectionName = request.sectionName, !sectionName.isEmpty {
            let sections = settings.sections(for: project.id)
            guard let section = findSection(named: sectionName, in: sections) else {
                return .failure("Section not found: \(sectionName)", id: request.id)
            }
            requestedSectionId = section.id
        } else if !hasExplicitSection, let fromThread, let fromSectionId = fromThread.sectionId {
            // Inherit section from from-thread when no explicit section was provided
            requestedSectionId = fromSectionId
        } else {
            requestedSectionId = nil
        }

        let thread: MagentThread
        do {
            let isPinnedSource = fromThread?.sidebarListState == .pinned
            thread = try await threadManager.createThread(
                project: project,
                requestedAgentType: requestedAgent,
                useAgentCommand: useAgentCommand,
                initialPrompt: request.prompt,
                shouldSubmitInitialPrompt: request.noSubmit != true,
                initialChatTab: {
                    guard selection.surface == .chat, let requestedAgent else { return nil }
                    return PersistedChatTab(
                        identifier: "chat:\(UUID().uuidString)",
                        agentType: requestedAgent,
                        title: TmuxSessionNaming.chatTabDisplayName(
                            for: requestedAgent,
                            modelLabel: threadManager.resolvedModelLabel(for: requestedAgent, modelId: request.modelId),
                            reasoningLevel: request.reasoningLevel
                        ),
                        draftInput: request.prompt ?? "",
                        modelId: request.modelId,
                        reasoningLevel: request.reasoningLevel
                    )
                }(),
                taskDescription: request.description,
                requestedBranchName: requestedName,
                requestedBaseBranch: requestedBaseBranch,
                requestedSectionId: requestedSectionId,
                insertAfterThreadId: isPinnedSource ? nil : fromThread?.id,
                insertAtTopOfVisibleGroup: isPinnedSource,
                skipAutoSelect: request.select != true,
                modelId: request.modelId,
                reasoningLevel: request.reasoningLevel
            )
        } catch {
            return .failure("Failed to create thread: \(error.localizedDescription)", id: request.id)
        }

        // Set priority from --priority if provided. `0` clears; out-of-range values
        // are clamped inside `setThreadPriority`.
        if let priority = request.priority {
            let clamped: Int? = (priority == 0) ? nil : priority
            try? threadManager.setThreadPriority(threadId: thread.id, priority: clamped)
        }

        let projectNameResolved = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? projectName
        guard let updatedThread = threadManager.threads.first(where: { $0.id == thread.id }) else {
            let info = IPCThreadInfo(thread: thread, projectName: projectNameResolved)
            return IPCResponse(ok: true, id: request.id, thread: info)
        }
        let info = IPCThreadInfo(thread: updatedThread, projectName: projectNameResolved)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    // MARK: - Batch Create

    private func batchCreateThreads(_ request: IPCRequest) async -> IPCResponse {
        guard let projectName = request.project else {
            return .failure("Missing required field: project", id: request.id)
        }
        guard let specs = request.threads, !specs.isEmpty else {
            return .failure("Missing required field: threads (array of thread specs)", id: request.id)
        }

        let settings = persistence.loadSettings()
        guard let project = settings.projects.first(where: {
            $0.name.caseInsensitiveCompare(projectName) == .orderedSame
        }) else {
            return .failure("Project not found: \(projectName)", id: request.id)
        }

        // Resolve request-level from-thread (auto-injected from $MAGENT_THREAD_ID or explicit --from-thread)
        let requestFromThread: MagentThread?
        switch resolveFromThread(
            fromThreadId: request.fromThreadId,
            fromThreadName: request.fromThreadName,
            project: project,
            requestId: request.id
        ) {
        case .none: requestFromThread = nil
        case .resolved(let t): requestFromThread = t
        case .error(let err): return err
        }

        // Phase 1: Resolve all names upfront (may involve AI slug generation).
        // This is sequential but lets us validate everything before creating anything.
        struct ResolvedSpec {
            let agentType: AgentType?
            let useAgentCommand: Bool
            let modelId: String?
            let modelLabel: String?
            let reasoningLevel: String?
            let prompt: String?
            let noSubmit: Bool
            let requestedName: String?
            let description: String?
            let requestedBaseBranch: String?
            let requestedSectionId: UUID?
            let fromThread: MagentThread?
            let priority: Int?
            let surface: AgentSurface?
        }

        var resolved: [ResolvedSpec] = []
        for (i, spec) in specs.enumerated() {
            let selection: IPCAgentSelection
            switch parseIPCAgentSelection(spec.agentType, chatsEnabled: settings.isChatsFeatureEnabled) {
            case .success(let parsed):
                selection = parsed
            case .failure(let message):
                return .failure("Thread \(i): \(message.description)", id: request.id)
            }
            let agentType = selection.agentType
            let useAgentCommand = selection.useAgentCommand

            // Resolve per-spec from-thread (falls back to request-level)
            let specFromThread: MagentThread?
            if let specFromName = spec.fromThreadName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !specFromName.isEmpty {
                switch resolveFromThread(
                    fromThreadId: nil,
                    fromThreadName: specFromName,
                    project: project,
                    requestId: request.id
                ) {
                case .none: specFromThread = nil
                case .resolved(let t): specFromThread = t
                case .error(let err): return err
                }
            } else {
                specFromThread = requestFromThread
            }

            // Resolve name from --name or --description
            let requestedName: String?
            if let exactName = spec.newName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !exactName.isEmpty {
                requestedName = exactName
            } else if let description = spec.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !description.isEmpty {
                let resolvedAgent = agentType ?? threadManager.resolveAgentType(
                    for: project.id, requestedAgentType: nil, settings: settings
                )
                let renameResult = await threadManager.autoRenameCandidates(
                    from: description, agentType: resolvedAgent, projectId: project.id
                )
                if case .candidates(let slugs) = renameResult {
                    requestedName = slugs.first
                } else {
                    requestedName = nil
                }
            } else {
                requestedName = nil
            }

            // Resolve base branch
            let hasExplicitBase = (spec.baseBranch != nil && !spec.baseBranch!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                (spec.baseThreadName != nil && !spec.baseThreadName!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            let baseBranch: String?
            if let bb = spec.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
               !bb.isEmpty {
                baseBranch = bb
            } else if let bt = spec.baseThreadName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !bt.isEmpty {
                guard let baseThread = threadManager.threads.first(where: {
                    $0.name.caseInsensitiveCompare(bt) == .orderedSame
                }) else {
                    return .failure("Thread \(i): base thread not found: \(bt)", id: request.id)
                }
                baseBranch = baseThread.actualBranch ?? baseThread.branchName
            } else if !hasExplicitBase, let ft = specFromThread, let inherited = branchFromThread(ft, project: project) {
                baseBranch = inherited
            } else {
                baseBranch = nil
            }

            // Resolve section
            let hasExplicitSection = spec.sectionName != nil &&
                !spec.sectionName!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let sectionId: UUID?
            if let sectionName = spec.sectionName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sectionName.isEmpty {
                let sections = settings.sections(for: project.id)
                guard let section = findSection(named: sectionName, in: sections) else {
                    return .failure("Thread \(i): section not found: \(sectionName)", id: request.id)
                }
                sectionId = section.id
            } else if !hasExplicitSection, let ft = specFromThread, let ftSection = ft.sectionId {
                sectionId = ftSection
            } else {
                sectionId = nil
            }

            // Resolve prompt — promptFile wins over inline prompt when both are provided.
            let resolvedPrompt: String?
            if let filePath = spec.promptFile?.trimmingCharacters(in: .whitespacesAndNewlines),
               !filePath.isEmpty {
                let url = URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath)
                do {
                    resolvedPrompt = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    return .failure("Thread \(i): could not read promptFile '\(filePath)': \(error.localizedDescription)", id: request.id)
                }
            } else {
                resolvedPrompt = spec.prompt
            }

            resolved.append(ResolvedSpec(
                agentType: agentType,
                useAgentCommand: useAgentCommand,
                modelId: spec.modelId,
                modelLabel: agentType.flatMap {
                    threadManager.resolvedModelLabel(for: $0, modelId: spec.modelId)
                },
                reasoningLevel: spec.reasoningLevel,
                prompt: resolvedPrompt,
                noSubmit: spec.noSubmit == true || request.noSubmit == true,
                requestedName: requestedName,
                description: spec.description,
                requestedBaseBranch: baseBranch,
                requestedSectionId: sectionId,
                fromThread: specFromThread,
                priority: spec.priority,
                surface: selection.surface
            ))
        }

        // Phase 2: Create threads concurrently. All specs passed validation,
        // so failures here are infrastructure-level (git/tmux).
        // Each thread passes skipAutoSelect: true so batch create doesn't jump focus.
        let results = await withTaskGroup(of: (Int, Result<MagentThread, Error>).self) { group in
            for (i, spec) in resolved.enumerated() {
                group.addTask { [threadManager] in
                    do {
                        // Don't pass insertAfterThreadId here — concurrent creates
                        // targeting the same fromThread would race on phase 1 ordering.
                        // A deterministic post-pass below handles positioning.
                        let thread = try await threadManager.createThread(
                            project: project,
                            requestedAgentType: spec.agentType,
                            useAgentCommand: spec.useAgentCommand,
                            initialPrompt: spec.prompt,
                            shouldSubmitInitialPrompt: !spec.noSubmit,
                            initialChatTab: {
                                guard spec.surface == .chat, let agentType = spec.agentType else { return nil }
                                return PersistedChatTab(
                                    identifier: "chat:\(UUID().uuidString)",
                                    agentType: agentType,
                                    title: TmuxSessionNaming.chatTabDisplayName(
                                        for: agentType,
                                        modelLabel: spec.modelLabel,
                                        reasoningLevel: spec.reasoningLevel
                                    ),
                                    draftInput: spec.prompt ?? "",
                                    modelId: spec.modelId,
                                    reasoningLevel: spec.reasoningLevel
                                )
                            }(),
                            taskDescription: spec.description,
                            requestedBranchName: spec.requestedName,
                            requestedBaseBranch: spec.requestedBaseBranch,
                            requestedSectionId: spec.requestedSectionId,
                            skipAutoSelect: true,
                            modelId: spec.modelId,
                            reasoningLevel: spec.reasoningLevel
                        )
                        return (i, .success(thread))
                    } catch {
                        return (i, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<MagentThread, Error>)] = []
            for await result in group {
                collected.append(result)
            }
            return collected.sorted(by: { $0.0 < $1.0 })
        }

        // Position new threads after their from-thread and set descriptions
        // (outside task group for main-actor safety, in request order for determinism).
        var needsSave = false
        for (i, result) in results {
            if case .success(let thread) = result {
                if let ft = resolved[i].fromThread {
                    if ft.sidebarListState == ThreadSidebarListState.pinned {
                        threadManager.bumpThreadToTopOfSection(thread.id)
                    } else {
                        threadManager.placeThreadAfterSibling(threadId: thread.id, afterThreadId: ft.id)
                    }
                    needsSave = true
                }
                if let p = resolved[i].priority {
                    let clamped: Int? = (p == 0) ? nil : p
                    try? threadManager.setThreadPriority(threadId: thread.id, priority: clamped)
                }
            }
        }
        if needsSave {
            try? threadManager.persistence.saveActiveThreads(threadManager.threads)
            await MainActor.run {
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }
        }

        // Build response with all created threads
        var threadInfos: [IPCThreadInfo] = []
        var errors: [String] = []
        for (i, result) in results {
            switch result {
            case .success(let thread):
                let updated = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
                threadInfos.append(IPCThreadInfo(thread: updated, projectName: projectName))
            case .failure(let error):
                errors.append("Thread \(i): \(error.localizedDescription)")
            }
        }

        if !errors.isEmpty, threadInfos.isEmpty {
            return .failure("All threads failed: \(errors.joined(separator: "; "))", id: request.id)
        }

        var response = IPCResponse(ok: true, id: request.id, threads: threadInfos)
        if !errors.isEmpty {
            response.warning = "Some threads failed: \(errors.joined(separator: "; "))"
        }
        return response
    }

    private func listProjects(_ request: IPCRequest) -> IPCResponse {
        let settings = persistence.loadSettings()
        let projects = settings.projects.map { IPCProjectInfo(project: $0) }
        let activeAgents = settings.availableActiveAgents.map(\.rawValue)
        return IPCResponse(ok: true, id: request.id, projects: projects, activeAgents: activeAgents)
    }

    private func listThreads(_ request: IPCRequest) -> IPCResponse {
        let settings = persistence.loadSettings()
        var threads = threadManager.threads

        if let projectName = request.project {
            if let project = settings.projects.first(where: {
                $0.name.caseInsensitiveCompare(projectName) == .orderedSame
            }) {
                threads = threads.filter { $0.projectId == project.id }
            } else {
                return .failure("Project not found: \(projectName)", id: request.id)
            }
        }

        let infos = threads.map { thread in
            let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
            var info = IPCThreadInfo(thread: thread, projectName: projectName)
            info.sectionName = resolveSectionName(for: thread, settings: settings)
            info.sectionId = thread.sectionId?.uuidString
            info.status = makeThreadStatus(for: thread)
            return info
        }
        return IPCResponse(ok: true, id: request.id, threads: infos)
    }

    /// Looks up an archived thread by ID or name from persistence. Archived threads are
    /// not present in `ThreadManager.threads`, so `resolveThread` can't find them.
    private func resolveArchivedThread(_ request: IPCRequest) -> MagentThread? {
        let archived = persistence.loadThreads().filter { $0.isArchived }
        if let threadId = request.threadId, let uuid = UUID(uuidString: threadId) {
            return archived.first(where: { $0.id == uuid })
        }
        if let name = request.threadName {
            return archived.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        }
        return nil
    }

    /// Lists archived threads (most recently archived first). Archived threads live in
    /// `threads.json` but not in `ThreadManager.threads`, so we load them from persistence.
    private func listArchived(_ request: IPCRequest) -> IPCResponse {
        let settings = persistence.loadSettings()

        let projectFilter: Project?
        if let projectName = request.project {
            guard let project = settings.projects.first(where: {
                $0.name.caseInsensitiveCompare(projectName) == .orderedSame
            }) else {
                return .failure("Project not found: \(projectName)", id: request.id)
            }
            projectFilter = project
        } else {
            projectFilter = nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var archived = persistence.loadThreads().filter { $0.isArchived && !$0.isMain }
        if let projectFilter {
            archived = archived.filter { $0.projectId == projectFilter.id }
        }
        // Most recently archived first; threads with no archivedAt sort last.
        archived.sort { lhs, rhs in
            switch (lhs.archivedAt, rhs.archivedAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return false
            }
        }

        if let limit = request.limit, limit > 0, archived.count > limit {
            archived = Array(archived.prefix(limit))
        }

        let infos = archived.map { thread -> IPCThreadInfo in
            let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
            return makeArchivedThreadInfo(thread: thread, projectName: projectName, settings: settings, isoFormatter: isoFormatter)
        }
        return IPCResponse(ok: true, id: request.id, threads: infos)
    }

    /// Builds a rich `IPCThreadInfo` for an archived thread. Archived threads aren't in
    /// `ThreadManager.threads`, so runtime status isn't meaningful — but persisted metadata
    /// (branch, worktree path, agent, Jira ticket, priority, icon, timestamps) is still
    /// useful for locating past work.
    private func makeArchivedThreadInfo(
        thread: MagentThread,
        projectName: String,
        settings: AppSettings,
        isoFormatter: ISO8601DateFormatter
    ) -> IPCThreadInfo {
        var info = IPCThreadInfo(thread: thread, projectName: projectName)
        info.sectionName = resolveSectionName(for: thread, settings: settings)
        info.sectionId = thread.sectionId?.uuidString
        info.branchName = thread.branchName
        info.baseBranch = thread.baseBranch
        info.worktreeName = (thread.worktreePath as NSString).lastPathComponent
        info.createdAt = isoFormatter.string(from: thread.createdAt)
        if let archivedAt = thread.archivedAt {
            info.archivedAt = isoFormatter.string(from: archivedAt)
        }
        // Pick the first agent session's type (if any) as the representative agent for this thread.
        if let firstAgentSession = thread.agentTmuxSessions.first,
           let agent = thread.sessionAgentTypes[firstAgentSession] {
            info.agentType = agent.rawValue
        } else if let anyAgent = thread.sessionAgentTypes.values.first {
            info.agentType = anyAgent.rawValue
        }
        if AppFeatures.jiraSyncEnabled {
            info.jiraTicketKey = thread.jiraTicketKey
        }
        info.isFavorite = thread.isFavorite
        info.isPinned = thread.isPinned
        info.isSidebarHidden = thread.isSidebarHidden
        info.priority = thread.priority
        info.signEmoji = thread.signEmoji
        info.threadIcon = thread.threadIcon.rawValue
        return info
    }

    private func sendPrompt(_ request: IPCRequest) async -> IPCResponse {
        guard let prompt = request.prompt, !prompt.isEmpty else {
            return .failure("Missing required field: prompt", id: request.id)
        }

        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        let selectedKind: ResolvedTabKind
        if request.sessionName != nil || request.tabIndex != nil {
            switch resolveTabSelection(request, in: thread) {
            case .resolved(let tab):
                selectedKind = tab.kind
            case .error(let err):
                return err
            }
        } else if let sessionName = thread.agentTmuxSessions.first ?? thread.tmuxSessionNames.first {
            selectedKind = .terminal(sessionName: sessionName, terminalDisplayIndex: 0)
        } else if let chatIdentifier = thread.persistedChatTabs.first?.identifier {
            selectedKind = .chat(identifier: chatIdentifier)
        } else {
            return .failure("Thread has no tabs that can accept prompts", id: request.id)
        }

        switch selectedKind {
        case .terminal(let sessionName, _):
            do {
                try await tmux.sendText(sessionName: sessionName, text: prompt)
                try? await Task.sleep(nanoseconds: 200_000_000)
                try await tmux.sendEnter(sessionName: sessionName)
            } catch {
                return .failure("Failed to send prompt: \(error.localizedDescription)", id: request.id)
            }

            if thread.agentTmuxSessions.contains(sessionName) {
                threadManager.scheduleAgentConversationIDRefresh(threadId: thread.id, sessionName: sessionName)
                threadManager.recordSubmittedPromptTiming(
                    threadId: thread.id,
                    sessionName: sessionName,
                    prompt: prompt
                )
                // Record in submitted history so auto-rename fires immediately,
                // without waiting for the user to open the thread or a bell event.
                threadManager.appendToSubmittedPromptHistory(
                    threadId: thread.id,
                    sessionName: sessionName,
                    prompt: prompt
                )
            }

            return .success(id: request.id)
        case .chat(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            var chatTabs = threadManager.threads[threadIndex].persistedChatTabs
            guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }

            let agentType = chatTabs[chatIndex].agentType
            let conversationSessionID = chatTabs[chatIndex].conversationSessionID
            let modelId = chatTabs[chatIndex].modelId
            let reasoningLevel = chatTabs[chatIndex].reasoningLevel
            let requestStateKey = chatRequestStateKey(threadID: thread.id, chatIdentifier: identifier)
            let submissionAction = await chatPromptCoordinator.prepareSubmission(
                key: requestStateKey,
                agentType: agentType,
                prompt: prompt
            )

            switch submissionAction {
            case .steered:
                chatTabs[chatIndex].messages = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
                    into: chatTabs[chatIndex].messages,
                    nextModelName: modelId,
                    nextModelId: modelId,
                    nextReasoningLevel: reasoningLevel
                )
                let steeringUser = PersistedChatMessage(
                    role: .user,
                    text: prompt,
                    modelId: modelId,
                    reasoningLevel: reasoningLevel
                )
                chatTabs[chatIndex].messages.append(steeringUser)
                threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: chatTabs)
                await MainActor.run {
                    threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
                }
                return .success(id: request.id)
            case .busy:
                return .failure(
                    "Chat request is already in progress for this tab. Wait for it to complete, or use a Codex chat tab for in-flight steering.",
                    id: request.id
                )
            case .start:
                break
            }

            chatTabs[chatIndex].messages = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
                into: chatTabs[chatIndex].messages,
                nextModelName: modelId,
                nextModelId: modelId,
                nextReasoningLevel: reasoningLevel
            )
            let user = PersistedChatMessage(
                role: .user,
                text: prompt,
                modelId: modelId,
                reasoningLevel: reasoningLevel
            )
            let pendingAssistant = PersistedChatMessage(
                role: .assistant,
                text: "Thinking…",
                modelId: modelId,
                reasoningLevel: reasoningLevel
            )
            chatTabs[chatIndex].messages.append(user)
            chatTabs[chatIndex].messages.append(pendingAssistant)
            let settings = persistence.loadSettings()

            threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: chatTabs)
            await MainActor.run {
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }

            let codexSteerStream: AsyncStream<String>?
            switch submissionAction {
            case .start(let steerStream):
                codexSteerStream = steerStream
            case .steered, .busy:
                codexSteerStream = nil
            }

            let response = await AgentChatRuntime.execute(
                agentType: agentType,
                prompt: prompt,
                workingDirectory: thread.worktreePath,
                conversationSessionID: conversationSessionID,
                claudeSystemPrompt: settings.ipcPromptInjectionEnabled ? IPCAgentDocs.claudeSystemPrompt : nil,
                codexDeveloperInstructions: settings.ipcPromptInjectionEnabled ? IPCAgentDocs.codexDeveloperInstructions : nil,
                modelId: modelId,
                reasoningLevel: reasoningLevel,
                codexSkipPermissions: settings.agentPermissionMode == .unrestricted,
                codexSandboxEnabled: settings.agentPermissionMode == .sandboxAuto,
                codexSteerStream: codexSteerStream
            )
            await chatPromptCoordinator.finishRequest(key: requestStateKey)

            guard let latestIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .success(id: request.id)
            }
            chatTabs = threadManager.threads[latestIndex].persistedChatTabs
            guard let latestChatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }),
                  let messageIndex = chatTabs[latestChatIndex].messages.firstIndex(where: { $0.id == pendingAssistant.id }) else {
                return .success(id: request.id)
            }

            chatTabs[latestChatIndex].messages[messageIndex].text = response.assistantText
            chatTabs[latestChatIndex].conversationSessionID = response.conversationSessionID
            threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: chatTabs)
            await MainActor.run {
                let isActiveTab = threadManager.activeThreadId == thread.id
                    && threadManager.threads.first(where: { $0.id == thread.id })?.lastSelectedTabIdentifier == identifier
                threadManager.markSessionCompletionDetected(
                    threadId: thread.id,
                    sessionName: identifier,
                    isActiveTab: isActiveTab
                )
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }
            return .success(id: request.id)
        case .web:
            return .failure("send-prompt is not supported for web tabs", id: request.id)
        case .draft:
            return .failure("send-prompt is not supported for draft tabs", id: request.id)
        }
    }

    private func chatRequestStateKey(threadID: UUID, chatIdentifier: String) -> String {
        "\(threadID.uuidString.lowercased())::\(chatIdentifier)"
    }

    private func startAgent(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        if request.threadName != nil || request.threadId != nil {
            switch resolveThread(request) {
            case .found(let t): thread = t
            case .error(let err): return err
            }
        } else if let sessionName = request.sessionName {
            guard let t = threadManager.threads.first(where: { $0.tmuxSessionNames.contains(sessionName) }) else {
                return .failure("No thread found for session: \(sessionName)", id: request.id)
            }
            thread = t
        } else {
            return .failure("Specify --session or --thread for start-agent", id: request.id)
        }

        let sessionName: String
        if request.sessionName != nil || request.tabIndex != nil {
            switch resolveTabSelection(request, in: thread) {
            case .resolved(let tab):
                guard case .terminal(let selectedSessionName, _) = tab.kind else {
                    return .failure("Selected tab is not a terminal tab", id: request.id)
                }
                sessionName = selectedSessionName
            case .error(let err):
                return err
            }
        } else if let firstAgentSession = thread.agentTmuxSessions.first {
            sessionName = firstAgentSession
        } else {
            return .failure("Thread has no agent terminal session", id: request.id)
        }

        guard thread.agentTmuxSessions.contains(sessionName) else {
            return .failure("Selected terminal tab is not an agent session", id: request.id)
        }

        if await threadManager.detectedAgentTypeInSession(sessionName) != nil {
            return .failure("An agent already appears to be running in this session", id: request.id)
        }

        await threadManager.refreshAgentConversationID(threadId: thread.id, sessionName: sessionName)
        guard let resolvedAgentType = threadManager.agentType(for: thread, sessionName: sessionName),
              let command = threadManager.agentShellStartCommand(
                sessionName: sessionName,
                agentType: resolvedAgentType
              ) else {
            return .failure("Could not build an agent start command for this session", id: request.id)
        }

        return IPCResponse(ok: true, id: request.id, shellCommand: command)
    }

    private func archiveThread(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        do {
            await MainActor.run {
                threadManager.markThreadArchiving(id: thread.id)
            }
            let syncOverride: Bool? = request.skipLocalSync == true ? false : nil
            let warning = try await threadManager.archiveThread(
                thread,
                force: request.force ?? false,
                syncLocalPathsBackToRepo: syncOverride,
                awaitLocalSync: true
            )
            return .success(id: request.id, warning: warning)
        } catch ThreadManagerError.dirtyWorktree(let worktreePath) {
            // Keep the refusal distinct from generic archive failures so CLI users
            // and coding agents see clearly that this is a safety stop, not a bug.
            let message = """
            Refusing to archive thread \"\(thread.name)\": worktree at \(worktreePath) has uncommitted or untracked changes.

            Options:
              1. Commit or stash the changes first, then re-run archive-thread.
              2. Discard the changes in that worktree if they are not needed.
              3. Re-run archive-thread after the worktree is clean.

            Note: `--force` does not bypass dirty-worktree refusal. It only allows archive to continue after non-conflict local-sync failures.
            """
            return .failure(message, id: request.id)
        } catch {
            return .failure("Failed to archive thread: \(error.localizedDescription)", id: request.id)
        }
    }

    private func deleteThread(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        do {
            try await threadManager.deleteThread(thread)
        } catch {
            return .failure("Failed to delete thread: \(error.localizedDescription)", id: request.id)
        }

        return .success(id: request.id)
    }

    // MARK: - Tab Commands

    private enum ResolvedTabKind {
        case terminal(sessionName: String, terminalDisplayIndex: Int)
        case web(identifier: String)
        case draft(identifier: String)
        case chat(identifier: String)
    }

    private struct ResolvedTab {
        let index: Int
        let kind: ResolvedTabKind
    }

    private enum TabSelectionResult {
        case resolved(ResolvedTab)
        case error(IPCResponse)
    }

    private func orderedTerminalSessions(for thread: MagentThread) -> [String] {
        let existing = thread.tmuxSessionNames
        let pinned = thread.pinnedTmuxSessions.filter(existing.contains)
        let unpinned = existing.filter { !pinned.contains($0) }
        return pinned + unpinned
    }

    /// Builds tab ordering to match the GUI tab strip:
    /// terminal (pinned + unpinned), then pinned web inserts into pinned region,
    /// then unpinned web, then draft tabs, then chat tabs.
    private func resolveTabs(for thread: MagentThread) -> [ResolvedTab] {
        var slots: [ResolvedTabKind] = []
        let orderedSessions = orderedTerminalSessions(for: thread)

        for (terminalDisplayIndex, sessionName) in orderedSessions.enumerated() {
            slots.append(.terminal(sessionName: sessionName, terminalDisplayIndex: terminalDisplayIndex))
        }

        var pinnedInsertIndex = thread.pinnedTmuxSessions.filter(orderedSessions.contains).count
        for persisted in thread.persistedWebTabs {
            let webKind: ResolvedTabKind = .web(identifier: persisted.identifier)
            if persisted.isPinned {
                let insertAt = min(pinnedInsertIndex, slots.count)
                slots.insert(webKind, at: insertAt)
                pinnedInsertIndex += 1
            } else {
                slots.append(webKind)
            }
        }

        for persisted in thread.persistedDraftTabs {
            let draftKind: ResolvedTabKind = .draft(identifier: persisted.identifier)
            if persisted.isPinned {
                let insertAt = min(pinnedInsertIndex, slots.count)
                slots.insert(draftKind, at: insertAt)
                pinnedInsertIndex += 1
            } else {
                slots.append(draftKind)
            }
        }
        for persisted in thread.persistedChatTabs {
            let chatKind: ResolvedTabKind = .chat(identifier: persisted.identifier)
            if persisted.isPinned {
                let insertAt = min(pinnedInsertIndex, slots.count)
                slots.insert(chatKind, at: insertAt)
                pinnedInsertIndex += 1
            } else {
                slots.append(chatKind)
            }
        }

        return slots.enumerated().map { ResolvedTab(index: $0.offset, kind: $0.element) }
    }

    private func buildIPCTabs(for thread: MagentThread) -> [IPCTabInfo] {
        let resolved = resolveTabs(for: thread)
        return resolved.map { entry in
            switch entry.kind {
            case .terminal(let sessionName, let terminalDisplayIndex):
                let isAgent = thread.agentTmuxSessions.contains(sessionName)
                var tab = IPCTabInfo(
                    index: entry.index,
                    sessionName: sessionName,
                    isAgent: isAgent,
                    tabType: "terminal"
                )
                tab.displayName = thread.displayName(for: sessionName, at: terminalDisplayIndex)
                tab.isPinned = thread.pinnedTmuxSessions.contains(sessionName)
                if isAgent {
                    tab.agentType = threadManager.agentType(for: thread, sessionName: sessionName)?.rawValue
                    tab.isBusy = thread.busySessions.contains(sessionName) || thread.magentBusySessions.contains(sessionName)
                    tab.isWaitingForInput = thread.waitingForInputSessions.contains(sessionName)
                    tab.hasUnreadCompletion = thread.unreadCompletionSessions.contains(sessionName)
                    tab.isBlockedByRateLimit = thread.rateLimitedSessions[sessionName] != nil
                }
                return tab
            case .web(let identifier):
                let persisted = thread.persistedWebTabs.first(where: { $0.identifier == identifier })
                var tab = IPCTabInfo(
                    index: entry.index,
                    sessionName: identifier,
                    isAgent: false,
                    tabType: "web"
                )
                tab.displayName = persisted?.displayTitle ?? "Web"
                tab.isPinned = persisted?.isPinned ?? false
                return tab
            case .draft(let identifier):
                let persisted = thread.persistedDraftTabs.first(where: { $0.identifier == identifier })
                var tab = IPCTabInfo(
                    index: entry.index,
                    sessionName: identifier,
                    isAgent: false,
                    tabType: "draft"
                )
                tab.displayName = "Draft"
                tab.isPinned = persisted?.isPinned ?? false
                return tab
            case .chat(let identifier):
                let persisted = thread.persistedChatTabs.first(where: { $0.identifier == identifier })
                var tab = IPCTabInfo(
                    index: entry.index,
                    sessionName: identifier,
                    isAgent: true,
                    tabType: "chat"
                )
                tab.displayName = persisted?.title ?? "Chat"
                tab.agentType = persisted?.agentType.rawValue
                tab.isPinned = persisted?.isPinned ?? false
                return tab
            }
        }
    }

    private func resolveTabSelection(_ request: IPCRequest, in thread: MagentThread) -> TabSelectionResult {
        let resolvedTabs = resolveTabs(for: thread)

        if let sessionName = request.sessionName?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionName.isEmpty {
            if let resolved = resolvedTabs.first(where: { tab in
                switch tab.kind {
                case .terminal(let s, _): return s == sessionName
                case .web(let id): return id == sessionName
                case .draft(let id): return id == sessionName
                case .chat(let id): return id == sessionName
                }
            }) {
                return .resolved(resolved)
            }
            return .error(.failure("Tab not found: \(sessionName)", id: request.id))
        }

        if let tabIndex = request.tabIndex {
            guard let resolved = resolvedTabs.first(where: { $0.index == tabIndex }) else {
                return .error(.failure("Invalid tab index: \(tabIndex)", id: request.id))
            }
            return .resolved(resolved)
        }

        return .error(.failure("Missing required field: tabIndex or sessionName", id: request.id))
    }

    private func tabIdentifier(from kind: ResolvedTabKind) -> String {
        switch kind {
        case .terminal(let sessionName, _): return sessionName
        case .web(let identifier): return identifier
        case .draft(let identifier): return identifier
        case .chat(let identifier): return identifier
        }
    }

    private func listTabs(_ request: IPCRequest) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        let tabs = buildIPCTabs(for: thread)
        return IPCResponse(ok: true, id: request.id, tabs: tabs)
    }

    private func readTab(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        let selected: ResolvedTab
        switch resolveTabSelection(request, in: thread) {
        case .resolved(let tab):
            selected = tab
        case .error(let err):
            return err
        }

        let latestThread = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
        let tabs = buildIPCTabs(for: latestThread)
        let nowISO: String = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: Date())
        }()

        switch selected.kind {
        case .terminal(let sessionName, _):
            let output: String?
            if let limit = request.limit, limit > 0 {
                output = await tmux.capturePane(sessionName: sessionName, lastLines: max(1, limit))
            } else {
                let fullCapture = await tmux.captureFullPane(sessionName: sessionName)
                if let fullCapture {
                    output = fullCapture
                } else {
                    output = await tmux.capturePane(sessionName: sessionName, lastLines: 200)
                }
            }

            let tabInfo = tabs.first(where: { $0.sessionName == sessionName })
            let transcript = IPCTabTranscript(
                tabType: "terminal",
                sessionName: sessionName,
                displayName: tabInfo?.displayName,
                source: "tmux",
                capturedAt: nowISO,
                content: output ?? "",
                chatMessages: nil
            )
            return IPCResponse(ok: true, id: request.id, transcript: transcript)
        case .chat(let identifier):
            guard let chatTab = latestThread.persistedChatTabs.first(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }

            let messages: [PersistedChatMessage]
            if let limit = request.limit, limit > 0 {
                messages = Array(chatTab.messages.suffix(limit))
            } else {
                messages = chatTab.messages
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let structured = messages.map { message in
                IPCChatTranscriptMessage(
                    role: message.role.rawValue,
                    text: message.text,
                    createdAt: formatter.string(from: message.createdAt)
                )
            }
            let content = structured.map { message in
                "[\(message.createdAt)] \(message.role):\n\(message.text)"
            }.joined(separator: "\n\n")

            let tabInfo = tabs.first(where: { $0.sessionName == identifier })
            let transcript = IPCTabTranscript(
                tabType: "chat",
                sessionName: identifier,
                displayName: tabInfo?.displayName ?? chatTab.title,
                source: "chat-persistence",
                capturedAt: nowISO,
                content: content,
                chatMessages: structured
            )
            return IPCResponse(ok: true, id: request.id, transcript: transcript)
        case .web:
            return .failure("Reading transcript is not supported for web tabs", id: request.id)
        case .draft:
            return .failure("Reading transcript is not supported for draft tabs", id: request.id)
        }
    }

    private func createTab(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        let useAgent: Bool
        let requestedAgent: AgentType?
        if let agentStr = request.agentType {
            if agentStr == "terminal" {
                useAgent = false
                requestedAgent = nil
            } else if let agent = AgentType(rawValue: agentStr) {
                useAgent = true
                requestedAgent = agent
            } else {
                return .failure("Unknown agent type: \(agentStr). Valid: claude, codex, custom, terminal", id: request.id)
            }
        } else {
            // Default to project/global default agent
            useAgent = !thread.agentTmuxSessions.isEmpty
            requestedAgent = nil
        }
        if let requestedAgent, !persistence.loadSettings().availableActiveAgents.contains(requestedAgent) {
            return .failure("Agent type is not enabled: \(requestedAgent.rawValue)", id: request.id)
        }

        do {
            let initialPrompt: String?
            if useAgent, let prompt = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                initialPrompt = prompt
            } else {
                initialPrompt = nil
            }
            let tab = try await threadManager.addTab(
                to: thread,
                useAgentCommand: useAgent,
                requestedAgentType: requestedAgent,
                initialPrompt: initialPrompt,
                startFresh: request.fresh == true,
                customTitle: requestedTabName(from: request),
                modelId: request.modelId,
                reasoningLevel: request.reasoningLevel
            )
            // Finalize session context (legacy pipe cleanup/rollback path, cwd enforcement)
            // — same as UI path.
            let latestThread = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
            _ = await threadManager.recreateSessionIfNeeded(
                sessionName: tab.tmuxSessionName,
                thread: latestThread
            )

            // Keep navigation/restoration in sync for externally created tabs.
            threadManager.updateLastSelectedTab(for: thread.id, identifier: tab.tmuxSessionName)
            if PopoutWindowManager.shared.isThreadPoppedOut(thread.id) {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .magentNavigateToThread,
                        object: nil,
                        userInfo: [
                            "threadId": thread.id,
                            "sessionName": tab.tmuxSessionName,
                        ]
                    )
                }
            }

            let updatedForTab = threadManager.threads.first(where: { $0.id == thread.id }) ?? latestThread
            if let info = buildIPCTabs(for: updatedForTab).first(where: { $0.sessionName == tab.tmuxSessionName }) {
                return IPCResponse(ok: true, id: request.id, tab: info)
            }

            let isAgent = useAgent
            let info = IPCTabInfo(
                index: tab.index,
                sessionName: tab.tmuxSessionName,
                isAgent: isAgent,
                tabType: "terminal"
            )
            return IPCResponse(ok: true, id: request.id, tab: info)
        } catch {
            return .failure("Failed to create tab: \(error.localizedDescription)", id: request.id)
        }
    }

    private func createWebTab(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard let rawURL = request.url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            return .failure("Missing required field: url", id: request.id)
        }
        guard let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https") else {
            return .failure("Invalid URL: \(rawURL). Must be a fully qualified http(s) URL.", id: request.id)
        }

        let customTitle = requestedTabName(from: request)
        let defaultTitle = url.host ?? "Web"
        let identifier = "web:\(UUID().uuidString)"

        var userInfo: [String: Any] = [
            "threadId": thread.id,
            "url": url,
            "identifier": identifier,
            // Keep the default title separate from customTitle so URL-host auto-title
            // behavior still has a fallback when a custom title is later cleared.
            "title": defaultTitle,
            "iconType": WebTabIconType.web.rawValue,
        ]
        if let customTitle {
            userInfo["customTitle"] = customTitle
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: .magentOpenExternalLinkInApp,
                object: nil,
                userInfo: userInfo
            )
        }

        let updatedForTab = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
        if let info = buildIPCTabs(for: updatedForTab).first(where: { $0.sessionName == identifier }) {
            return IPCResponse(ok: true, id: request.id, tab: info)
        }

        let approximateIndex = resolveTabs(for: thread).count
        var info = IPCTabInfo(index: approximateIndex, sessionName: identifier, isAgent: false, tabType: "web")
        info.displayName = customTitle ?? defaultTitle
        return IPCResponse(ok: true, id: request.id, tab: info)
    }

    private func autoRenameThread(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        let prompt = [request.prompt, request.description, request.newName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let prompt else {
            return .failure("Missing required field: prompt", id: request.id)
        }

        let renameResult = await threadManager.autoRenameCandidates(
            from: prompt,
            agentType: threadManager.effectiveAgentType(for: thread.projectId),
            projectId: thread.projectId
        )
        guard case .candidates(let candidates) = renameResult else {
            return .failure("Could not generate a branch name from the prompt", id: request.id)
        }

        var didRename = false
        let renameCandidates = candidates.filter { $0 != thread.branchName }
        for candidate in renameCandidates {
            do {
                try await threadManager.renameThread(thread, to: candidate, markFirstPromptRenameHandled: false)
                didRename = true
                break
            } catch ThreadManagerError.duplicateName {
                continue
            } catch {
                return .failure("Failed to rename branch: \(error.localizedDescription)", id: request.id)
            }
        }

        if !renameCandidates.isEmpty, !didRename {
            return .failure("All generated branch name candidates are taken", id: request.id)
        }

        _ = await threadManager.regenerateTaskDescription(threadId: thread.id, prompt: prompt)

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        // Warning applies only to agent-generated descriptions from this command.
        let warning = updated.taskDescription.flatMap(descriptionPreferenceWarning)
        return IPCResponse(ok: true, id: request.id, warning: warning, thread: info)
    }

    private func renameBranch(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard let newName = request.newName, !newName.isEmpty else {
            return .failure("Missing required field: name (pass via newName)", id: request.id)
        }

        do {
            try await threadManager.renameThread(thread, to: newName, markFirstPromptRenameHandled: false)
        } catch {
            return .failure("Failed to rename branch: \(error.localizedDescription)", id: request.id)
        }

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setDescription(_ request: IPCRequest) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        do {
            try threadManager.setTaskDescription(threadId: thread.id, description: request.description)
        } catch {
            return .failure("Failed to set description: \(error.localizedDescription)", id: request.id)
        }

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setPriority(_ request: IPCRequest) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        // `remove == true` or explicit `0` clears the priority. Otherwise use the
        // integer value (clamped inside the setter to 1...5).
        let priority: Int?
        if request.remove == true {
            priority = nil
        } else if let p = request.priority {
            priority = (p == 0) ? nil : p
        } else {
            return .failure("Missing required field: priority (1-5) or --clear", id: request.id)
        }

        do {
            try threadManager.setThreadPriority(threadId: thread.id, priority: priority)
        } catch {
            return .failure("Failed to set priority: \(error.localizedDescription)", id: request.id)
        }

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setThreadIcon(_ request: IPCRequest) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard let iconRaw = request.icon?.trimmingCharacters(in: .whitespacesAndNewlines),
              !iconRaw.isEmpty else {
            return .failure("Missing required field: icon", id: request.id)
        }

        guard let icon = ThreadIcon(rawValue: iconRaw) else {
            let validIcons = ThreadIcon.allCases.map(\.rawValue).joined(separator: ", ")
            return .failure("Unknown icon: \(iconRaw). Valid: \(validIcons)", id: request.id)
        }

        do {
            try threadManager.setThreadIcon(threadId: thread.id, icon: icon)
        } catch {
            return .failure("Failed to set thread icon: \(error.localizedDescription)", id: request.id)
        }

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setBaseBranch(_ request: IPCRequest) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard let baseBranch = request.baseBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseBranch.isEmpty else {
            return .failure("Missing required field: baseBranch", id: request.id)
        }

        threadManager.setBaseBranch(baseBranch, for: thread.id)

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let resolvedBase = threadManager.resolveBaseBranch(for: updated)
        let info = IPCThreadInfo(thread: updated, projectName: projectName, baseBranch: resolvedBase)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setThreadHidden(_ request: IPCRequest, hidden: Bool) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        if thread.isMain {
            return .failure("Main threads cannot be hidden", id: request.id)
        }

        guard thread.isSidebarHidden != hidden else {
            let settings = persistence.loadSettings()
            let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
            let info = IPCThreadInfo(thread: thread, projectName: projectName)
            return IPCResponse(ok: true, id: request.id, thread: info)
        }

        threadManager.toggleThreadHidden(threadId: thread.id)

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setThreadFavorite(_ request: IPCRequest, favorite: Bool) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard thread.isFavorite != favorite else {
            let settings = persistence.loadSettings()
            let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
            let info = IPCThreadInfo(thread: thread, projectName: projectName)
            return IPCResponse(ok: true, id: request.id, thread: info)
        }

        if favorite && !threadManager.canAddFavoriteThread(excludingThreadId: thread.id) {
            return .failure("Favorites limit reached (\(ThreadManager.maxFavoriteThreadCount)). Remove a favorite first.", id: request.id)
        }

        _ = threadManager.toggleThreadFavorite(threadId: thread.id)

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setThreadKeepAlive(_ request: IPCRequest, enabled: Bool) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard thread.isKeepAlive != enabled else {
            let settings = persistence.loadSettings()
            let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
            let info = IPCThreadInfo(thread: thread, projectName: projectName)
            return IPCResponse(ok: true, id: request.id, thread: info)
        }

        threadManager.toggleThreadKeepAlive(threadId: thread.id)

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setTabKeepAlive(_ request: IPCRequest, enabled: Bool) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard let sessionName = request.sessionName, !sessionName.isEmpty else {
            return .failure("Missing required field: sessionName (pass via --session)", id: request.id)
        }

        guard thread.tmuxSessionNames.contains(sessionName) else {
            return .failure("Session not found in thread: \(sessionName)", id: request.id)
        }

        let isProtected = thread.protectedTmuxSessions.contains(sessionName)
        guard isProtected != enabled else {
            let settings = persistence.loadSettings()
            let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
            let info = IPCThreadInfo(thread: thread, projectName: projectName)
            return IPCResponse(ok: true, id: request.id, thread: info)
        }

        threadManager.toggleSessionKeepAlive(threadId: thread.id, sessionName: sessionName)

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let info = IPCThreadInfo(thread: updated, projectName: projectName)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func setTabPinned(_ request: IPCRequest, pinned: Bool) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        let selected: ResolvedTab
        switch resolveTabSelection(request, in: thread) {
        case .resolved(let tab):
            selected = tab
        case .error(let err):
            return err
        }

        let updatedIdentifier: String
        switch selected.kind {
        case .terminal(let sessionName, let terminalDisplayIndex):
            guard terminalDisplayIndex > 0 else {
                return .failure("Cannot pin the fixed Terminal tab", id: request.id)
            }
            guard thread.tmuxSessionNames.contains(sessionName) else {
                return .failure("Session not found in thread: \(sessionName)", id: request.id)
            }

            var pinnedSessions = thread.pinnedTmuxSessions.filter { thread.tmuxSessionNames.contains($0) }
            let alreadyPinned = pinnedSessions.contains(sessionName)
            if pinned, !alreadyPinned {
                pinnedSessions.append(sessionName)
            } else if !pinned, alreadyPinned {
                pinnedSessions.removeAll { $0 == sessionName }
            }

            if pinnedSessions != thread.pinnedTmuxSessions {
                threadManager.updatePinnedTabs(for: thread.id, pinnedSessions: pinnedSessions)
            }
            updatedIdentifier = sessionName
        case .web(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            var webTabs = threadManager.threads[threadIndex].persistedWebTabs
            guard let webIndex = webTabs.firstIndex(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }
            if webTabs[webIndex].isPinned != pinned {
                webTabs[webIndex].isPinned = pinned
                threadManager.updatePersistedWebTabs(for: thread.id, webTabs: webTabs)
            }
            updatedIdentifier = identifier
        case .draft(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            var draftTabs = threadManager.threads[threadIndex].persistedDraftTabs
            guard let draftIndex = draftTabs.firstIndex(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }
            if draftTabs[draftIndex].isPinned != pinned {
                draftTabs[draftIndex].isPinned = pinned
                threadManager.updatePersistedDraftTabs(for: thread.id, draftTabs: draftTabs)
            }
            updatedIdentifier = identifier
        case .chat(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            var chatTabs = threadManager.threads[threadIndex].persistedChatTabs
            guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }
            if chatTabs[chatIndex].isPinned != pinned {
                chatTabs[chatIndex].isPinned = pinned
                threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: chatTabs)
            }
            updatedIdentifier = identifier
        }

        DispatchQueue.main.async {
            self.threadManager.delegate?.threadManager(self.threadManager, didUpdateThreads: self.threadManager.threads)
        }

        guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
            return .success(id: request.id)
        }
        let tabInfo = buildIPCTabs(for: updated).first { tab in
            tab.sessionName == updatedIdentifier
        }
        return IPCResponse(ok: true, id: request.id, tab: tabInfo)
    }

    private func setSectionKeepAlive(_ request: IPCRequest, enabled: Bool) -> IPCResponse {
        guard let sectionName = request.sectionName, !sectionName.isEmpty else {
            return .failure("Missing required field: sectionName", id: request.id)
        }

        var settings = persistence.loadSettings()
        let (project, error) = resolveProjectForSection(request, settings: settings)
        if let error { return error }

        if let project {
            let projectIndex = settings.projects.firstIndex(where: { $0.id == project.id })!
            var sections = settings.projects[projectIndex].threadSections ?? settings.threadSections
            guard let sectionIndex = sections.firstIndex(where: { $0.name.caseInsensitiveCompare(sectionName) == .orderedSame }) else {
                return .failure("Section not found: \(sectionName)", id: request.id)
            }
            guard sections[sectionIndex].isKeepAlive != enabled else { return .success(id: request.id) }
            sections[sectionIndex].isKeepAlive = enabled
            settings.projects[projectIndex].threadSections = sections
            try? persistence.saveSettings(settings)
        } else {
            guard let sectionIndex = settings.threadSections.firstIndex(where: { $0.name.caseInsensitiveCompare(sectionName) == .orderedSame }) else {
                return .failure("Section not found: \(sectionName)", id: request.id)
            }
            guard settings.threadSections[sectionIndex].isKeepAlive != enabled else { return .success(id: request.id) }
            settings.threadSections[sectionIndex].isKeepAlive = enabled
            try? persistence.saveSettings(settings)
        }

        notifySectionsDidChange()
        NotificationCenter.default.post(name: .magentKeepAliveChanged, object: nil)
        return .success(id: request.id)
    }

    private func currentThread(_ request: IPCRequest) -> IPCResponse {
        guard let sessionName = request.sessionName, !sessionName.isEmpty else {
            return .failure("Missing required field: sessionName", id: request.id)
        }

        guard let thread = threadManager.threads.first(where: { $0.tmuxSessionNames.contains(sessionName) }) else {
            return .failure("No thread found for session: \(sessionName)", id: request.id)
        }

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        let resolvedBase = threadManager.resolveBaseBranch(for: thread)
        let info = IPCThreadInfo(thread: thread, projectName: projectName, baseBranch: resolvedBase)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func threadInfo(_ request: IPCRequest) -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err):
            // Fall back to archived threads in persistence so callers can introspect
            // recently archived threads (branch name, worktree path, timestamps, etc.).
            if let archived = resolveArchivedThread(request) {
                let settings = persistence.loadSettings()
                let projectName = settings.projects.first(where: { $0.id == archived.projectId })?.name ?? "unknown"
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime]
                let info = makeArchivedThreadInfo(thread: archived, projectName: projectName, settings: settings, isoFormatter: isoFormatter)
                return IPCResponse(ok: true, id: request.id, thread: info)
            }
            return err
        }

        let settings = persistence.loadSettings()
        let projectName = settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "unknown"
        let sectionName = resolveSectionName(for: thread, settings: settings)

        // Build tab list across terminal/web/draft/chat in GUI display order.
        let tabs = buildIPCTabs(for: thread)

        let status = makeThreadStatus(for: thread)

        let info = IPCThreadInfo(thread: thread, projectName: projectName, sectionName: sectionName, tabs: tabs, status: status)
        return IPCResponse(ok: true, id: request.id, thread: info)
    }

    private func resolveSectionName(for thread: MagentThread, settings: AppSettings) -> String? {
        let sections = settings.sections(for: thread.projectId)
        if let sectionId = thread.sectionId,
           let section = sections.first(where: { $0.id == sectionId }) {
            return section.name
        }
        return settings.defaultSection(for: thread.projectId)?.name
    }

    func makeThreadStatus(for thread: MagentThread) -> IPCThreadStatus {
        IPCThreadStatus(
            isBusy: thread.isAnyBusy,
            isWaitingForInput: thread.hasWaitingForInput,
            hasUnreadCompletion: thread.hasUnreadAgentCompletion,
            isDirty: thread.isDirty,
            isFullyDelivered: thread.isFullyDelivered,
            showArchiveSuggestion: thread.showArchiveSuggestion,
            isPinned: thread.isPinned,
            isFavorite: thread.isFavorite,
            isSidebarHidden: thread.isSidebarHidden,
            isArchived: thread.isArchived,
            isBlockedByRateLimit: thread.isBlockedByRateLimit,
            hasBranchMismatch: thread.hasBranchMismatch,
            jiraTicketKey: AppFeatures.jiraSyncEnabled ? thread.jiraTicketKey : nil,
            jiraUnassigned: AppFeatures.jiraSyncEnabled ? thread.jiraUnassigned : false,
            branchName: thread.branchName,
            baseBranch: thread.baseBranch,
            rateLimitDescription: thread.isBlockedByRateLimit ? thread.rateLimitLiftDescription : nil
        )
    }

    private func renameTab(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        guard let rawName = request.newName else {
            return .failure("Missing required field: newName (pass via --name)", id: request.id)
        }
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        let selected: ResolvedTab
        switch resolveTabSelection(request, in: thread) {
        case .resolved(let tab):
            selected = tab
        case .error(let err):
            return err
        }

        switch selected.kind {
        case .terminal(let sessionName, _):
            guard !trimmedName.isEmpty else {
                return .failure("Tab name must not be empty for terminal/agent tabs", id: request.id)
            }

            do {
                try await threadManager.renameTab(
                    threadId: thread.id,
                    sessionName: sessionName,
                    newDisplayName: trimmedName
                )
            } catch {
                return .failure("Failed to rename tab: \(error.localizedDescription)", id: request.id)
            }

            guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
                return .success(id: request.id)
            }

            // Session name can change after tmux rename; locate by display index fallback.
            let resolved = resolveTabs(for: updated)
            let updatedEntry = resolved.first(where: { tab in
                if case .terminal(let candidate, _) = tab.kind {
                    return candidate == sessionName
                }
                return false
            }) ?? resolved.first(where: { $0.index == selected.index })

            guard let updatedEntry else { return .success(id: request.id) }
            let tabInfo = buildIPCTabs(for: updated).first(where: { $0.index == updatedEntry.index })
            if let tabInfo {
                return IPCResponse(ok: true, id: request.id, tab: tabInfo)
            }
            return .success(id: request.id)
        case .web(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            guard let webIndex = threadManager.threads[threadIndex].persistedWebTabs.firstIndex(where: {
                $0.identifier == identifier
            }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }

            var webTabs = threadManager.threads[threadIndex].persistedWebTabs
            webTabs[webIndex].customTitle = trimmedName.isEmpty ? nil : trimmedName
            threadManager.updatePersistedWebTabs(for: thread.id, webTabs: webTabs)
            await MainActor.run {
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }

            guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
                return .success(id: request.id)
            }
            if let tabInfo = buildIPCTabs(for: updated).first(where: { $0.sessionName == identifier }) {
                return IPCResponse(ok: true, id: request.id, tab: tabInfo)
            }
            return .success(id: request.id)
        case .draft:
            return .failure("Rename is not supported for draft tabs", id: request.id)
        case .chat(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            guard let chatIndex = threadManager.threads[threadIndex].persistedChatTabs.firstIndex(where: {
                $0.identifier == identifier
            }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }
            guard !trimmedName.isEmpty else {
                return .failure("Tab name must not be empty", id: request.id)
            }

            var chatTabs = threadManager.threads[threadIndex].persistedChatTabs
            chatTabs[chatIndex].title = trimmedName
            chatTabs[chatIndex].isTitleManuallySet = true
            threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: chatTabs)
            await MainActor.run {
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }

            guard let updated = threadManager.threads.first(where: { $0.id == thread.id }) else {
                return .success(id: request.id)
            }
            if let tabInfo = buildIPCTabs(for: updated).first(where: { $0.sessionName == identifier }) {
                return IPCResponse(ok: true, id: request.id, tab: tabInfo)
            }
            return .success(id: request.id)
        }
    }

    private func closeTab(_ request: IPCRequest) async -> IPCResponse {
        let thread: MagentThread
        switch resolveThread(request) {
        case .found(let t): thread = t
        case .error(let err): return err
        }

        let resolvedTabs = resolveTabs(for: thread)
        guard resolvedTabs.count > 1 else {
            return .failure("Cannot close the last tab — use archive-thread or delete-thread instead", id: request.id)
        }

        let selected: ResolvedTab
        switch resolveTabSelection(request, in: thread) {
        case .resolved(let tab):
            selected = tab
        case .error(let err):
            return err
        }

        switch selected.kind {
        case .terminal(let sessionName, _):
            do {
                try await threadManager.removeTab(from: thread, sessionName: sessionName)
            } catch {
                return .failure("Failed to close tab: \(error.localizedDescription)", id: request.id)
            }
            return .success(id: request.id)
        case .web(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            var webTabs = threadManager.threads[threadIndex].persistedWebTabs
            guard webTabs.contains(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }
            webTabs.removeAll { $0.identifier == identifier }
            threadManager.updatePersistedWebTabs(for: thread.id, webTabs: webTabs)

            if threadManager.threads[threadIndex].lastSelectedTabIdentifier == identifier {
                let updated = threadManager.threads[threadIndex]
                let fallbackIdentifier = resolveTabs(for: updated).first.map { tabIdentifier(from: $0.kind) }
                threadManager.updateLastSelectedTab(for: thread.id, identifier: fallbackIdentifier)
            }

            await MainActor.run {
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }
            return .success(id: request.id)
        case .draft(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            var draftTabs = threadManager.threads[threadIndex].persistedDraftTabs
            guard draftTabs.contains(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }
            draftTabs.removeAll { $0.identifier == identifier }
            threadManager.updatePersistedDraftTabs(for: thread.id, draftTabs: draftTabs)

            if threadManager.threads[threadIndex].lastSelectedTabIdentifier == identifier {
                let updated = threadManager.threads[threadIndex]
                let fallbackIdentifier = resolveTabs(for: updated).first.map { tabIdentifier(from: $0.kind) }
                threadManager.updateLastSelectedTab(for: thread.id, identifier: fallbackIdentifier)
            }

            await MainActor.run {
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }
            return .success(id: request.id)
        case .chat(let identifier):
            guard let threadIndex = threadManager.threads.firstIndex(where: { $0.id == thread.id }) else {
                return .failure("Thread not found: \(thread.name)", id: request.id)
            }
            var chatTabs = threadManager.threads[threadIndex].persistedChatTabs
            guard chatTabs.contains(where: { $0.identifier == identifier }) else {
                return .failure("Tab not found: \(identifier)", id: request.id)
            }
            chatTabs.removeAll { $0.identifier == identifier }
            threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: chatTabs)

            if threadManager.threads[threadIndex].lastSelectedTabIdentifier == identifier {
                let updated = threadManager.threads[threadIndex]
                let fallbackIdentifier = resolveTabs(for: updated).first.map { tabIdentifier(from: $0.kind) }
                threadManager.updateLastSelectedTab(for: thread.id, identifier: fallbackIdentifier)
            }

            await MainActor.run {
                threadManager.delegate?.threadManager(threadManager, didUpdateThreads: threadManager.threads)
            }
            return .success(id: request.id)
        }
    }
}
