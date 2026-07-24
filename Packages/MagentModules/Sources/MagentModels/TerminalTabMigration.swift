import Foundation

public nonisolated enum TabMoveRecoveryFailureStage: Sendable, Equatable {
    case recoveryScan
    case sourceThreadUnavailable
    case sourceWorktreeInspection
    case sourceWorktreeChanged
    case destinationCleanup
    case sourceRestore
    case redundantStashCleanup

    public var retryScope: TabMoveRecoveryRetryScope? {
        switch self {
        case .redundantStashCleanup:
            return .redundantStashCleanup
        case .recoveryScan, .sourceThreadUnavailable, .sourceWorktreeInspection,
             .sourceWorktreeChanged, .destinationCleanup, .sourceRestore:
            return nil
        }
    }
}

public nonisolated enum TabMoveRecoveryRetryScope: Sendable, Equatable {
    case redundantStashCleanup
}

public nonisolated struct TabMoveRecoveryBannerPolicy: Sendable, Equatable {
    public let stages: [TabMoveRecoveryFailureStage]

    public init(stages: [TabMoveRecoveryFailureStage]) {
        self.stages = stages
    }

    public var retryScope: TabMoveRecoveryRetryScope? {
        guard !stages.isEmpty,
              stages.allSatisfy({ $0.retryScope == .redundantStashCleanup }) else {
            return nil
        }
        return .redundantStashCleanup
    }
}

public nonisolated struct TerminalTabMigration: Sendable, Equatable {
    public let sourceThreadID: UUID
    public let sourceSessionName: String
    public let displayName: String
    public let agentType: AgentType
    public let conversationID: String
    public let wasManuallyRenamed: Bool
    public let wasForwardedContinuation: Bool
    public let wasPinned: Bool
    public let wasProtected: Bool
    public let hadUnreadCompletion: Bool
    public let hadUnreadRateLimit: Bool
    public let submittedPrompts: [String]

    public init(
        sourceThreadID: UUID,
        sourceSessionName: String,
        displayName: String,
        agentType: AgentType,
        conversationID: String,
        wasManuallyRenamed: Bool,
        wasForwardedContinuation: Bool,
        wasPinned: Bool,
        wasProtected: Bool,
        hadUnreadCompletion: Bool,
        hadUnreadRateLimit: Bool,
        submittedPrompts: [String]
    ) {
        self.sourceThreadID = sourceThreadID
        self.sourceSessionName = sourceSessionName
        self.displayName = displayName
        self.agentType = agentType
        self.conversationID = conversationID
        self.wasManuallyRenamed = wasManuallyRenamed
        self.wasForwardedContinuation = wasForwardedContinuation
        self.wasPinned = wasPinned
        self.wasProtected = wasProtected
        self.hadUnreadCompletion = hadUnreadCompletion
        self.hadUnreadRateLimit = hadUnreadRateLimit
        self.submittedPrompts = submittedPrompts
    }
}

public extension MagentThread {
    func terminalTabMigration(for sessionName: String) -> TerminalTabMigration? {
        guard let sessionIndex = tmuxSessionNames.firstIndex(of: sessionName),
              agentTmuxSessions.contains(sessionName),
              let agentType = sessionAgentTypes[sessionName],
              agentType.supportsResume,
              let conversationID = sessionConversationIDs[sessionName]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !conversationID.isEmpty else {
            return nil
        }

        return TerminalTabMigration(
            sourceThreadID: id,
            sourceSessionName: sessionName,
            displayName: displayName(for: sessionName, at: sessionIndex),
            agentType: agentType,
            conversationID: conversationID,
            wasManuallyRenamed: manuallyRenamedTabs.contains(sessionName),
            wasForwardedContinuation: forwardedTmuxSessions.contains(sessionName),
            wasPinned: pinnedTmuxSessions.contains(sessionName),
            wasProtected: isKeepAlive || protectedTmuxSessions.contains(sessionName),
            hadUnreadCompletion: unreadCompletionSessions.contains(sessionName),
            hadUnreadRateLimit: unreadRateLimitSessions.contains(sessionName),
            submittedPrompts: submittedPromptsBySession[sessionName] ?? []
        )
    }

    mutating func installMigratedTerminalTab(
        _ migration: TerminalTabMigration,
        sessionName: String,
        createdAt: Date
    ) {
        tmuxSessionNames = [sessionName]
        agentTmuxSessions = [sessionName]
        sessionConversationIDs = [sessionName: migration.conversationID]
        sessionAgentTypes = [sessionName: migration.agentType]
        sessionCreatedAts = [sessionName: createdAt]
        customTabNames = [sessionName: migration.displayName]
        submittedPromptsBySession = migration.submittedPrompts.isEmpty
            ? [:]
            : [sessionName: migration.submittedPrompts]
        lastSelectedTabIdentifier = sessionName
        agentHasRun = true

        if migration.wasManuallyRenamed {
            manuallyRenamedTabs.insert(sessionName)
        }
        if migration.wasForwardedContinuation {
            forwardedTmuxSessions.insert(sessionName)
        }
        if migration.wasPinned {
            pinnedTmuxSessions = [sessionName]
        }
        if migration.wasProtected {
            protectedTmuxSessions.insert(sessionName)
        }
        if migration.hadUnreadCompletion {
            unreadCompletionSessions.insert(sessionName)
        }
        if migration.hadUnreadRateLimit {
            unreadRateLimitSessions.insert(sessionName)
        }
    }

    mutating func removeMigratedTerminalTab(sessionName: String) {
        tmuxSessionNames.removeAll { $0 == sessionName }
        agentTmuxSessions.removeAll { $0 == sessionName }
        sessionConversationIDs.removeValue(forKey: sessionName)
        sessionAgentTypes.removeValue(forKey: sessionName)
        sessionCreatedAts.removeValue(forKey: sessionName)
        freshAgentSessions.remove(sessionName)
        forwardedTmuxSessions.remove(sessionName)
        pinnedTmuxSessions.removeAll { $0 == sessionName }
        protectedTmuxSessions.remove(sessionName)
        unreadCompletionSessions.remove(sessionName)
        unreadRateLimitSessions.remove(sessionName)
        busySessions.remove(sessionName)
        magentBusySessions.remove(sessionName)
        waitingForInputSessions.remove(sessionName)
        hasUnsubmittedInputSessions.remove(sessionName)
        rateLimitedSessions.removeValue(forKey: sessionName)
        customTabNames.removeValue(forKey: sessionName)
        manuallyRenamedTabs.remove(sessionName)
        submittedPromptsBySession.removeValue(forKey: sessionName)
        deadSessions.remove(sessionName)

        if lastSelectedTabIdentifier == sessionName {
            lastSelectedTabIdentifier = tmuxSessionNames.first
                ?? persistedWebTabs.first?.identifier
                ?? persistedDraftTabs.first?.identifier
                ?? persistedChatTabs.first?.identifier
        }
    }
}
