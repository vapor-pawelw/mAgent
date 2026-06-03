import Cocoa
import MagentCore

extension ThreadDetailViewController {
    private static let chatLoadingPlaceholder = "Thinking..."

    // MARK: - Restore (In-memory)

    func restoreChatTabItems() {
        var restoredTabsMutated = false
        chatTabs = thread.persistedChatTabs.map { persisted in
            let reconciledMessages: (messages: [PersistedChatMessage], didMutate: Bool)
            if persisted.agentType == .codex, let conversationSessionID = persisted.conversationSessionID {
                reconciledMessages = CodexChatTranscriptReconciler.reconciledMessages(
                    existingMessages: persisted.messages,
                    codexSessionID: conversationSessionID
                )
            } else if persisted.agentType == .claude, let conversationSessionID = persisted.conversationSessionID {
                reconciledMessages = ClaudeChatTranscriptReconciler.reconciledMessages(
                    existingMessages: persisted.messages,
                    claudeSessionID: conversationSessionID
                )
            } else {
                reconciledMessages = (messages: persisted.messages, didMutate: false)
            }
            let normalizedMessages: (messages: [PersistedChatMessage], didMutate: Bool)
            if reconciledMessages.didMutate {
                normalizedMessages = (messages: reconciledMessages.messages, didMutate: false)
            } else {
                normalizedMessages = ChatBusyStateRecovery.normalizedMessagesForAppRelaunch(reconciledMessages.messages)
            }
            if normalizedMessages.didMutate {
                restoredTabsMutated = true
            }
            if reconciledMessages.didMutate {
                restoredTabsMutated = true
            }
            return ChatTabEntry(
                identifier: persisted.identifier,
                agentType: persisted.agentType,
                title: persisted.title,
                messages: normalizedMessages.messages,
                draftInput: persisted.draftInput,
                draftAttachments: persisted.draftAttachments,
                conversationSessionID: persisted.conversationSessionID,
                modelId: persisted.modelId,
                reasoningLevel: persisted.reasoningLevel,
                isPinned: persisted.isPinned,
                viewController: nil
            )
        }

        if restoredTabsMutated {
            persistChatTabs()
        }

        for entry in chatTabs {
            let item = TabItemView(title: entry.title)
            item.showCloseButton = true
            attachDragGesture(to: item)
            applyChatTabIcon(to: item)

            if entry.isPinned {
                tabItems.insert(item, at: pinnedCount)
                tabSlots.insert(.chat(identifier: entry.identifier), at: pinnedCount)
                pinnedCount += 1
            } else {
                tabItems.append(item)
                tabSlots.append(.chat(identifier: entry.identifier))
            }
        }
    }

    func applyChatTabIcon(to item: TabItemView) {
        item.typeIcon.image = NSImage(systemSymbolName: "message.fill", accessibilityDescription: "Chat")
        item.typeIcon.contentTintColor = .secondaryLabelColor
        item.typeIcon.isHidden = false
    }

    // MARK: - Open

    func openChatTab(
        identifier: String,
        agentType: AgentType,
        title: String = "Chat",
        messages: [PersistedChatMessage] = [],
        draftInput: String = "",
        draftAttachments: [PersistedChatAttachment] = [],
        conversationSessionID: String? = nil,
        modelId: String? = nil,
        reasoningLevel: String? = nil,
        initialPrompt: String? = nil
    ) {
        if let existingIndex = tabSlots.firstIndex(of: .chat(identifier: identifier)) {
            selectTab(at: existingIndex)
            if let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
                submitChatPrompt(identifier: identifier, text: prompt)
            }
            return
        }

        hideEmptyState()

        let entry = ChatTabEntry(
            identifier: identifier,
            agentType: agentType,
            title: title,
            messages: messages,
            draftInput: draftInput,
            draftAttachments: draftAttachments,
            conversationSessionID: conversationSessionID,
            modelId: modelId,
            reasoningLevel: reasoningLevel,
            isPinned: false,
            viewController: nil
        )
        chatTabs.append(entry)
        persistChatTabs()

        let item = TabItemView(title: title)
        item.showCloseButton = true
        attachDragGesture(to: item)
        applyChatTabIcon(to: item)

        tabItems.append(item)
        tabSlots.append(.chat(identifier: identifier))

        rebindAllTabActions()
        rebuildTabBar()

        let newIndex = tabItems.count - 1
        selectTab(at: newIndex)

        if let prompt = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            submitChatPrompt(identifier: identifier, text: prompt)
        }
    }

    // MARK: - Select

    func selectChatTab(identifier: String, displayIndex: Int) {
        for termView in terminalViews { termView.isHidden = true }
        hideActiveWebTab()
        hideActiveDraftTab()
        hideActiveChatTab()
        for (_, placeholder) in detachedTabPlaceholders {
            placeholder.isHidden = true
        }

        for (i, item) in tabItems.enumerated() {
            item.isSelected = (i == displayIndex)
        }

        activeChatTabId = identifier
        currentTabIndex = displayIndex
        postFocusedThreadContextChangedIfKeyWindow()
        persistChatSelection(identifier: identifier, displayIndex: displayIndex)

        guard let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else {
            dismissLoadingOverlay()
            return
        }

        if chatTabs[entryIndex].viewController == nil {
            // Building a chat view with a long transcript can be expensive because
            // it creates and lays out every message bubble. Commit the tab-bar
            // selection first, then materialize the chat on the next run-loop turn
            // so the click gives immediate visual feedback instead of looking like
            // a frozen UI.
            ensureLoadingOverlay()
            loadingLabel?.stringValue = "Loading chat…"
            loadingDetailLabel?.isHidden = true
            revealLoadingOverlay(after: 0)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.activeChatTabId == identifier,
                      self.currentTabIndex == displayIndex else { return }
                self.materializeSelectedChatTab(identifier: identifier, displayIndex: displayIndex)
            }
            return
        }

        materializeSelectedChatTab(identifier: identifier, displayIndex: displayIndex)
    }

    private func materializeSelectedChatTab(identifier: String, displayIndex: Int) {
        guard activeChatTabId == identifier,
              displayIndex < tabItems.count,
              tabSlots.indices.contains(displayIndex),
              case .chat(let selectedIdentifier) = tabSlots[displayIndex],
              selectedIdentifier == identifier,
              let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else {
            return
        }

        if chatTabs[entryIndex].viewController == nil {
            let entry = chatTabs[entryIndex]
            let vc = ChatTabViewController(
                identifier: identifier,
                agentType: entry.agentType,
                messages: entry.messages,
                draftInput: entry.draftInput,
                draftAttachments: entry.draftAttachments,
                modelId: entry.modelId,
                reasoningLevel: entry.reasoningLevel,
                pendingQueuedUserMessageIDs: queuedPendingUserMessageIDs(for: identifier)
            )
            vc.onSubmit = { [weak self] text, attachments in
                self?.submitChatPrompt(identifier: identifier, text: text, attachments: attachments)
            }
            vc.isCommandRunning = { [weak self] in
                self?.isChatRequestRunning(identifier: identifier) ?? false
            }
            vc.onCancelRunningCommand = { [weak self] in
                self?.cancelInFlightChatRequest(identifier: identifier)
            }
            vc.onOpenMarkdownLink = { [weak self] target in
                self?.handleChatMarkdownLinkTap(target)
            }
            vc.onDraftChanged = { [weak self] draftInput in
                self?.updateChatDraftInput(identifier: identifier, draftInput: draftInput)
            }
            vc.onDraftAttachmentsChanged = { [weak self] draftAttachments in
                self?.updateChatDraftAttachments(identifier: identifier, draftAttachments: draftAttachments)
            }
            vc.onModelReasoningChanged = { [weak self] modelId, reasoningLevel in
                self?.updateChatModelReasoning(identifier: identifier, modelId: modelId, reasoningLevel: reasoningLevel)
            }
            chatTabs[entryIndex].viewController = vc
        }

        guard let vc = chatTabs[entryIndex].viewController else { return }

        vc.update(
            agentType: chatTabs[entryIndex].agentType,
            messages: chatTabs[entryIndex].messages,
            draftInput: chatTabs[entryIndex].draftInput,
            draftAttachments: chatTabs[entryIndex].draftAttachments,
            modelId: chatTabs[entryIndex].modelId,
            reasoningLevel: chatTabs[entryIndex].reasoningLevel,
            pendingQueuedUserMessageIDs: queuedPendingUserMessageIDs(for: identifier)
        )

        if vc.view.superview == nil {
            vc.view.translatesAutoresizingMaskIntoConstraints = false
            terminalContainer.addSubview(vc.view)
            NSLayoutConstraint.activate([
                vc.view.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                vc.view.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                vc.view.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
                vc.view.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
            ])
        }

        vc.view.isHidden = false
        terminalContainer.addSubview(vc.view, positioned: .above, relativeTo: nil)
        vc.setRelativeTimeUpdatesEnabled(true)
        vc.focusComposer()
        dismissLoadingOverlay()

        refreshTabTooltips()

        // Chat is a GUI tab type, not a terminal surface.
        scrollOverlay.isHidden = true
        setScrollFABVisible(false)
        promptTOCCanShowForCurrentTab = false
        applyPromptTOCVisibility()
    }

    private func persistChatSelection(identifier: String, displayIndex: Int) {
        if thread.lastSelectedTabIdentifier != identifier {
            thread.lastSelectedTabIdentifier = identifier
            threadManager.updateLastSelectedTab(for: thread.id, identifier: identifier)
        }
        UserDefaults.standard.set(thread.id.uuidString, forKey: Self.lastOpenedThreadDefaultsKey)
        UserDefaults.standard.set(identifier, forKey: Self.lastOpenedTabDefaultsKey)
        if displayIndex < tabItems.count {
            tabItems[displayIndex].hasUnreadCompletion = false
        }
        threadManager.markSessionCompletionSeen(threadId: thread.id, sessionName: identifier)
    }

    func hideActiveChatTab() {
        guard let activeId = activeChatTabId,
              let entry = chatTabs.first(where: { $0.identifier == activeId }) else { return }
        entry.viewController?.setRelativeTimeUpdatesEnabled(false)
        entry.viewController?.view.isHidden = true
        activeChatTabId = nil
    }

    // MARK: - Close

    func closeChatTab(identifier: String) {
        let alert = NSAlert()
        alert.messageText = "Close Chat Tab?"
        alert.informativeText = "This will close the chat tab. Are you sure?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: .CommonStrings.commonClose))
        alert.addButton(withTitle: String(localized: .CommonStrings.commonCancel))

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        removeChatTab(identifier: identifier)
    }

    func removeChatTab(identifier: String) {
        guard let slotIndex = tabSlots.firstIndex(of: .chat(identifier: identifier)) else { return }
        cancelInFlightChatRequest(identifier: identifier)
        chatSteerInputContinuationsByIdentifier[identifier]?.finish()
        chatSteerInputContinuationsByIdentifier.removeValue(forKey: identifier)
        chatQueuedPromptsByIdentifier.removeValue(forKey: identifier)
        chatStreamingCheckpointTasksByIdentifier[identifier]?.cancel()
        chatStreamingCheckpointTasksByIdentifier.removeValue(forKey: identifier)
        threadManager.markSessionCompletionSeen(threadId: thread.id, sessionName: identifier)

        let persistedSnapshot = thread.persistedChatTabs.first(where: { $0.identifier == identifier })
        if let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) {
            chatTabs[entryIndex].viewController?.view.removeFromSuperview()
            chatTabs.remove(at: entryIndex)
        }
        if let persistedSnapshot {
            threadManager.pushClosedTabSnapshot(.chat(persistedSnapshot), for: thread.id)
        }
        persistChatTabs()

        if activeChatTabId == identifier {
            activeChatTabId = nil
        }

        tabItems.remove(at: slotIndex)
        tabSlots.remove(at: slotIndex)
        rebindAllTabActions()
        rebuildTabBar()

        if tabItems.isEmpty {
            showEmptyState()
        } else {
            let newIndex = min(currentTabIndex, tabItems.count - 1)
            selectTab(at: newIndex)
        }
    }

    // MARK: - Rename

    func showChatTabRenameDialog(at displayIndex: Int) {
        guard displayIndex < tabSlots.count, displayIndex < tabItems.count,
              case .chat(let identifier) = tabSlots[displayIndex],
              let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }

        let currentTitle = chatTabs[chatIndex].title

        let alert = NSAlert()
        alert.messageText = String(localized: .ThreadStrings.tabRenameTitle)
        alert.informativeText = String(localized: .ThreadStrings.tabRenameMessage)
        alert.addButton(withTitle: String(localized: .CommonStrings.commonRename))
        alert.addButton(withTitle: String(localized: .CommonStrings.commonCancel))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        textField.stringValue = currentTitle
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newTitle = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != currentTitle else { return }

        chatTabs[chatIndex].title = newTitle
        tabItems[displayIndex].titleLabel.stringValue = newTitle
        persistChatTabs()
        refreshTabTooltips()
    }

    // MARK: - Continue In

    func presentContinueChatTabSheet(for index: Int) {
        guard index < tabSlots.count, case .chat(let identifier) = tabSlots[index] else { return }
        guard let window = view.window else { return }
        guard let chatEntry = chatTabs.first(where: { $0.identifier == identifier }) else { return }

        let settings = PersistenceService.shared.loadSettings()
        let agents = settings.availableActiveAgents.filter { $0 != chatEntry.agentType }
        guard !agents.isEmpty else {
            NSSound.beep()
            return
        }

        let config = AgentLaunchSheetConfig(
            title: "Continue In",
            acceptButtonTitle: "Continue",
            draftScope: .newTab(threadId: thread.id),
            availableAgents: agents,
            defaultAgentType: agents.first,
            isAgentOnly: true,
            subtitle: chatContinueSubtitle(),
            showDescriptionAndBranchFields: false,
            showTitleField: true,
            autoGenerateHint: nil,
            terminalInjectionPrefill: nil,
            agentContextPrefill: nil,
            showPromptInputArea: true,
            showDraftCheckbox: false,
            promptLabelOverride: "Extra context"
        )
        let controller = AgentLaunchPromptSheetController(config: config)
        controller.present(for: window) { [weak self] result in
            guard let self, let result, let agentType = result.agentType else { return }
            let switchToTab = PersistenceService.shared.loadSettings().switchToNewlyCreatedTab
            let extraContext = result.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.continueChatTabInAgent(
                at: index,
                targetAgent: agentType,
                extraContext: extraContext?.isEmpty == false ? extraContext : nil,
                customTitle: result.tabTitle,
                modelId: result.modelId,
                reasoningLevel: result.reasoningLevel,
                switchToTab: switchToTab
            )
        }
    }

    func continueChatTabInAgent(
        at index: Int,
        targetAgent: AgentType,
        extraContext: String? = nil,
        customTitle: String? = nil,
        modelId: String? = nil,
        reasoningLevel: String? = nil,
        switchToTab: Bool = true
    ) {
        guard index < tabSlots.count, case .chat(let identifier) = tabSlots[index] else { return }
        guard let chatEntry = chatTabs.first(where: { $0.identifier == identifier }) else { return }

        let settings = PersistenceService.shared.loadSettings()
        let project = settings.projects.first(where: { $0.id == thread.projectId })
        let projectName = project?.name ?? "project"

        guard let contextBasePath = project?.resolvedWorktreesBasePath() else {
            BannerManager.shared.show(message: String(localized: .NotificationStrings.contextWriteFileFailed), style: .error)
            return
        }

        let markdown = chatConversationMarkdown(chatEntry: chatEntry, projectName: projectName)
        guard let contextPath = ContextExporter.writeContextFile(markdown: markdown, inWorktreesBasePath: contextBasePath) else {
            BannerManager.shared.show(message: String(localized: .NotificationStrings.contextWriteFileFailed), style: .error)
            return
        }

        let prompt = ContextExporter.transferPrompt(contextFilePath: contextPath, extraContext: extraContext)
        let trimmedCustomTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (trimmedCustomTitle?.isEmpty == false)
            ? trimmedCustomTitle!
            : "\(targetAgent.displayName) Chat"
        let previousSelectedIndex = currentTabIndex

        openChatTab(
            identifier: "chat:\(UUID().uuidString)",
            agentType: targetAgent,
            title: title,
            modelId: modelId,
            reasoningLevel: reasoningLevel,
            initialPrompt: prompt
        )

        if !switchToTab, tabItems.count > 1 {
            let restoredIndex = min(previousSelectedIndex, tabItems.count - 2)
            selectTab(at: max(0, restoredIndex))
        }

        if let modelId {
            AgentLastSelectionStore.saveModel(modelId, for: targetAgent)
        }
        if let reasoningLevel {
            AgentLastSelectionStore.saveReasoning(reasoningLevel, for: targetAgent, modelId: modelId)
        }
    }

    // MARK: - Export

    func exportChatTabConversation(at displayIndex: Int) {
        guard displayIndex < tabSlots.count, case .chat(let identifier) = tabSlots[displayIndex] else { return }
        guard let chatEntry = chatTabs.first(where: { $0.identifier == identifier }) else { return }

        let settings = PersistenceService.shared.loadSettings()
        let project = settings.projects.first(where: { $0.id == thread.projectId })
        let projectName = project?.name ?? "project"
        let markdown = chatConversationMarkdown(chatEntry: chatEntry, projectName: projectName)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = chatExportDefaultFileName(for: chatEntry.title)
        panel.title = String(localized: .NotificationStrings.contextExport)

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            BannerManager.shared.show(
                message: String(localized: .NotificationStrings.contextExported(url.lastPathComponent)),
                style: .info
            )
        } catch {
            BannerManager.shared.show(
                message: String(localized: .NotificationStrings.contextExportFailed(error.localizedDescription)),
                style: .error
            )
        }
    }

    // MARK: - Messaging

    private func handleChatMarkdownLinkTap(_ rawTarget: String) {
        switch ChatMarkdownLinkResolver.resolve(rawTarget, workingDirectory: thread.worktreePath) {
        case .web(let url):
            openChatMarkdownWebTab(url)
        case .localFile(let location):
            openChatMarkdownFileDestination(location)
        case nil:
            NSSound.beep()
        }
    }

    private func openChatMarkdownWebTab(_ url: URL) {
        guard supportsInAppWebTab(for: url) else {
            NSWorkspace.shared.open(url)
            return
        }
        openWebTab(
            url: url,
            identifier: "web:\(UUID().uuidString)",
            title: WebURLNormalizer.shortHost(from: url) ?? "Web",
            iconType: .web
        )
    }

    private func openChatMarkdownFileDestination(_ location: ChatMarkdownFileLocation) {
        let fileURL = location.url
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            NSSound.beep()
            return
        }
        if isDirectory.boolValue {
            NSWorkspace.shared.open(fileURL)
        } else {
            if let line = location.line, openFileInXcodeAtLine(fileURL, line: line) {
                return
            }
            NSWorkspace.shared.open(fileURL)
        }
    }

    private func openFileInXcodeAtLine(_ fileURL: URL, line: Int) -> Bool {
        guard line > 0 else { return false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xed", "--line", String(line), fileURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func queuedPendingUserMessageIDs(for identifier: String) -> Set<UUID> {
        Set((chatQueuedPromptsByIdentifier[identifier] ?? []).map(\.messageID))
    }

    private func refreshChatTabView(chatIndex: Int) {
        guard chatTabs.indices.contains(chatIndex) else { return }
        let entry = chatTabs[chatIndex]
        entry.viewController?.update(
            agentType: entry.agentType,
            messages: entry.messages,
            draftInput: entry.draftInput,
            draftAttachments: entry.draftAttachments,
            modelId: entry.modelId,
            reasoningLevel: entry.reasoningLevel,
            pendingQueuedUserMessageIDs: queuedPendingUserMessageIDs(for: entry.identifier)
        )
    }

    private func submitChatPrompt(identifier: String, text: String, attachments: [PersistedChatAttachment] = []) {
        guard let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAttachments = normalizeAttachmentsForSubmission(attachments)
        guard !trimmedText.isEmpty || !normalizedAttachments.isEmpty else { return }
        if normalizedAttachments.isEmpty,
           handleChatSlashCommandIfNeeded(identifier: identifier, chatIndex: entryIndex, text: trimmedText) {
            return
        }
        guard chatRequestTasksByIdentifier[identifier] == nil else {
            if chatTabs[entryIndex].agentType == .codex,
               normalizedAttachments.isEmpty,
               !trimmedText.isEmpty,
               let steerContinuation = chatSteerInputContinuationsByIdentifier[identifier] {
                let metadata = chatMessageMetadata(for: entryIndex)
                chatTabs[entryIndex].messages = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
                    into: chatTabs[entryIndex].messages,
                    nextModelName: chatModelDisplayName(for: entryIndex, modelId: metadata.modelId),
                    nextModelId: metadata.modelId,
                    nextReasoningLevel: metadata.reasoningLevel
                )
                let steeringMessage = PersistedChatMessage(
                    role: .user,
                    text: trimmedText,
                    modelId: metadata.modelId,
                    reasoningLevel: metadata.reasoningLevel
                )
                chatTabs[entryIndex].messages.append(steeringMessage)
                persistChatTabs()
                refreshChatTabView(chatIndex: entryIndex)
                steerContinuation.yield(trimmedText)
                return
            }

            let metadata = chatMessageMetadata(for: entryIndex)
            chatTabs[entryIndex].messages = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
                into: chatTabs[entryIndex].messages,
                nextModelName: chatModelDisplayName(for: entryIndex, modelId: metadata.modelId),
                nextModelId: metadata.modelId,
                nextReasoningLevel: metadata.reasoningLevel
            )
            let queuedUserMessage = PersistedChatMessage(
                role: .user,
                text: trimmedText,
                attachments: normalizedAttachments,
                modelId: metadata.modelId,
                reasoningLevel: metadata.reasoningLevel
            )
            chatTabs[entryIndex].messages.append(queuedUserMessage)
            enqueueChatPrompt(
                identifier: identifier,
                messageID: queuedUserMessage.id,
                text: trimmedText,
                attachments: normalizedAttachments
            )
            persistChatTabs()
            refreshChatTabView(chatIndex: entryIndex)
            return
        }

        startChatPromptRequest(
            identifier: identifier,
            promptText: trimmedText,
            attachments: normalizedAttachments,
            chatIndex: entryIndex
        )
    }

    private func startChatPromptRequest(
        identifier: String,
        promptText: String,
        attachments: [PersistedChatAttachment],
        chatIndex: Int,
        existingQueuedUserMessageID: UUID? = nil
    ) {
        // Defensive cleanup: if a previous request died unexpectedly and left one or
        // more loading placeholders behind, remove them before starting a new turn.
        let normalizedMessages = ChatBusyStateRecovery.normalizedMessagesForNewRequest(
            chatTabs[chatIndex].messages
        )
        if normalizedMessages.didMutate {
            chatTabs[chatIndex].messages = normalizedMessages.messages
        }

        let metadata = chatMessageMetadata(for: chatIndex)
        let preparedAttachments = prepareAttachmentsForAgentSubmission(attachments, worktreePath: thread.worktreePath)
        chatTabs[chatIndex].messages = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
            into: chatTabs[chatIndex].messages,
            nextModelName: chatModelDisplayName(for: chatIndex, modelId: metadata.modelId),
            nextModelId: metadata.modelId,
            nextReasoningLevel: metadata.reasoningLevel
        )
        if let existingQueuedUserMessageID,
           !chatTabs[chatIndex].messages.contains(where: { $0.id == existingQueuedUserMessageID }) {
            let reconstructedUser = PersistedChatMessage(
                id: existingQueuedUserMessageID,
                role: .user,
                text: promptText,
                attachments: preparedAttachments,
                modelId: metadata.modelId,
                reasoningLevel: metadata.reasoningLevel
            )
            chatTabs[chatIndex].messages.append(reconstructedUser)
        } else if let existingQueuedUserMessageID,
                  let existingIndex = chatTabs[chatIndex].messages.firstIndex(where: { $0.id == existingQueuedUserMessageID }) {
            chatTabs[chatIndex].messages[existingIndex].text = promptText
            chatTabs[chatIndex].messages[existingIndex].attachments = preparedAttachments
            chatTabs[chatIndex].messages[existingIndex].modelId = metadata.modelId
            chatTabs[chatIndex].messages[existingIndex].reasoningLevel = metadata.reasoningLevel
        }
        if existingQueuedUserMessageID == nil {
            let user = PersistedChatMessage(
                role: .user,
                text: promptText,
                attachments: preparedAttachments,
                modelId: metadata.modelId,
                reasoningLevel: metadata.reasoningLevel
            )
            chatTabs[chatIndex].messages.append(user)
        }
        let pendingAssistant = PersistedChatMessage(
            role: .assistant,
            text: Self.chatLoadingPlaceholder,
            modelId: metadata.modelId,
            reasoningLevel: metadata.reasoningLevel
        )
        chatTabs[chatIndex].messages.append(pendingAssistant)
        chatPendingAssistantMessageIDsByIdentifier[identifier] = pendingAssistant.id
        chatStreamingAssistantMessageIDsByIdentifier[identifier] = [:]
        chatStreamingCheckpointTasksByIdentifier[identifier]?.cancel()
        chatStreamingCheckpointTasksByIdentifier.removeValue(forKey: identifier)
        persistChatTabs()
        refreshChatTabView(chatIndex: chatIndex)

        let worktreePath = thread.worktreePath
        let settings = PersistenceService.shared.loadSettings()
        let permissionMode = settings.agentPermissionMode
        let codexSkipPermissions = permissionMode == .unrestricted
        let codexSandboxEnabled = permissionMode == .sandboxAuto
        let includeMagentIPC = settings.ipcPromptInjectionEnabled
        let agentType = chatTabs[chatIndex].agentType
        let conversationSessionID = chatTabs[chatIndex].conversationSessionID
        let selectedModelId = chatTabs[chatIndex].modelId
        let selectedReasoningLevel = chatTabs[chatIndex].reasoningLevel
        let taskToken = UUID()
        let codexSteerStream = makeCodexSteerStreamIfNeeded(identifier: identifier, agentType: agentType)
        chatRequestTaskTokensByIdentifier[identifier] = taskToken

        let task = Task { [weak self] in
            guard let self else { return }
            let response = await AgentChatRuntime.execute(
                agentType: agentType,
                prompt: promptText,
                workingDirectory: worktreePath,
                conversationSessionID: conversationSessionID,
                claudeSystemPrompt: includeMagentIPC ? IPCAgentDocs.claudeSystemPrompt : nil,
                codexDeveloperInstructions: includeMagentIPC ? IPCAgentDocs.codexDeveloperInstructions : nil,
                modelId: selectedModelId,
                reasoningLevel: selectedReasoningLevel,
                codexSkipPermissions: codexSkipPermissions,
                codexSandboxEnabled: codexSandboxEnabled,
                attachments: self.agentChatAttachments(from: preparedAttachments),
                codexSteerStream: codexSteerStream,
                onStreamingUpdate: { [weak self] update in
                    guard let self else { return }
                    guard self.chatRequestTaskTokensByIdentifier[identifier] == taskToken else { return }
                    self.applyStreamingAssistantUpdate(
                        identifier: identifier,
                        pendingAssistantID: pendingAssistant.id,
                        metadata: metadata,
                        update: update
                    )
                }
            )

            await MainActor.run {
                guard self.chatRequestTaskTokensByIdentifier[identifier] == taskToken else { return }
                self.chatRequestTasksByIdentifier.removeValue(forKey: identifier)
                self.chatRequestTaskTokensByIdentifier.removeValue(forKey: identifier)
                self.chatSteerInputContinuationsByIdentifier[identifier]?.finish()
                self.chatSteerInputContinuationsByIdentifier.removeValue(forKey: identifier)
                self.chatStreamingCheckpointTasksByIdentifier[identifier]?.cancel()
                self.chatStreamingCheckpointTasksByIdentifier.removeValue(forKey: identifier)
                guard let currentIndex = self.chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
                let streamedMessageIDs = Set((self.chatStreamingAssistantMessageIDsByIdentifier[identifier] ?? [:]).values)
                let hasRenderedStreamedMessages = self.chatTabs[currentIndex].messages.contains(where: {
                    streamedMessageIDs.contains($0.id)
                })

                if let pendingMessageID = self.chatPendingAssistantMessageIDsByIdentifier.removeValue(forKey: identifier),
                   let pendingIndex = self.chatTabs[currentIndex].messages.firstIndex(where: { $0.id == pendingMessageID }) {
                    self.chatTabs[currentIndex].messages.remove(at: pendingIndex)
                }

                let finalText = self.normalizeFinalAssistantMessage(
                    response.assistantText
                )
                let reconciledMessages = ChatFinalAssistantMessageReconciler.messagesByReconcilingFinalAssistantText(
                    self.chatTabs[currentIndex].messages,
                    streamedMessageIDs: hasRenderedStreamedMessages ? streamedMessageIDs : [],
                    finalText: finalText,
                    modelId: metadata.modelId,
                    reasoningLevel: metadata.reasoningLevel
                )
                self.chatTabs[currentIndex].messages = reconciledMessages.messages

                self.chatStreamingAssistantMessageIDsByIdentifier.removeValue(forKey: identifier)
                self.chatTabs[currentIndex].conversationSessionID = response.conversationSessionID
                self.syncChatModelReasoningFromAgentMessage(chatIndex: currentIndex, output: response.assistantText)
                self.persistChatTabs()
                self.refreshChatTabView(chatIndex: currentIndex)
                self.refreshTabStatusIndicators()
                let isActiveChatTab = self.activeChatTabId == identifier
                self.threadManager.markSessionCompletionDetected(
                    threadId: self.thread.id,
                    sessionName: identifier,
                    isActiveTab: isActiveChatTab
                )
                self.dispatchQueuedChatPromptIfNeeded(identifier: identifier)
            }
        }
        // A very fast failure can complete before this assignment line executes.
        // Register the task only when its token is still current to avoid reviving
        // a finished task as "running".
        if chatRequestTaskTokensByIdentifier[identifier] == taskToken {
            chatRequestTasksByIdentifier[identifier] = task
        }
        refreshTabStatusIndicators()
    }

    func isChatRequestRunning(identifier: String) -> Bool {
        chatRequestTasksByIdentifier[identifier] != nil
    }

    func cancelInFlightChatRequest(identifier: String) {
        guard let task = chatRequestTasksByIdentifier[identifier] else { return }
        task.cancel()
        chatRequestTasksByIdentifier.removeValue(forKey: identifier)
        chatRequestTaskTokensByIdentifier.removeValue(forKey: identifier)
        chatSteerInputContinuationsByIdentifier[identifier]?.finish()
        chatSteerInputContinuationsByIdentifier.removeValue(forKey: identifier)
        chatStreamingAssistantMessageIDsByIdentifier.removeValue(forKey: identifier)
        chatStreamingCheckpointTasksByIdentifier[identifier]?.cancel()
        chatStreamingCheckpointTasksByIdentifier.removeValue(forKey: identifier)

        if let pendingMessageID = chatPendingAssistantMessageIDsByIdentifier.removeValue(forKey: identifier),
           let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }),
           let messageIndex = chatTabs[entryIndex].messages.firstIndex(where: { $0.id == pendingMessageID }) {
            chatTabs[entryIndex].messages[messageIndex].text = "Request cancelled."
            persistChatTabs()
            refreshChatTabView(chatIndex: entryIndex)
        }

        refreshTabStatusIndicators()
        dispatchQueuedChatPromptIfNeeded(identifier: identifier)
    }

    private func enqueueChatPrompt(
        identifier: String,
        messageID: UUID,
        text: String,
        attachments: [PersistedChatAttachment]
    ) {
        var queue = chatQueuedPromptsByIdentifier[identifier] ?? []
        queue.append((messageID: messageID, text: text, attachments: attachments))
        chatQueuedPromptsByIdentifier[identifier] = queue
    }

    private func dispatchQueuedChatPromptIfNeeded(identifier: String) {
        guard chatRequestTasksByIdentifier[identifier] == nil else { return }
        guard var queue = chatQueuedPromptsByIdentifier[identifier], !queue.isEmpty else { return }
        let nextPrompt = queue.removeFirst()
        if queue.isEmpty {
            chatQueuedPromptsByIdentifier.removeValue(forKey: identifier)
        } else {
            chatQueuedPromptsByIdentifier[identifier] = queue
        }
        guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        startChatPromptRequest(
            identifier: identifier,
            promptText: nextPrompt.text,
            attachments: nextPrompt.attachments,
            chatIndex: chatIndex,
            existingQueuedUserMessageID: nextPrompt.messageID
        )
    }

    private func applyStreamingAssistantUpdate(
        identifier: String,
        pendingAssistantID: UUID,
        metadata: (modelId: String?, reasoningLevel: String?),
        update: AgentChatStreamingUpdate
    ) {
        guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }

        var messageIDsByItem = chatStreamingAssistantMessageIDsByIdentifier[identifier] ?? [:]
        let bubbleMessageID = messageIDsByItem[update.itemID]
        let trimmedText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if let bubbleMessageID,
           let messageIndex = chatTabs[chatIndex].messages.firstIndex(where: { $0.id == bubbleMessageID }) {
            chatTabs[chatIndex].messages[messageIndex].text = trimmedText
            chatTabs[chatIndex].messages[messageIndex].modelId = metadata.modelId
            chatTabs[chatIndex].messages[messageIndex].reasoningLevel = metadata.reasoningLevel
        } else {
            let assistantMessage = PersistedChatMessage(
                role: .assistant,
                text: trimmedText,
                modelId: metadata.modelId,
                reasoningLevel: metadata.reasoningLevel
            )
            if let pendingIndex = chatTabs[chatIndex].messages.firstIndex(where: { $0.id == pendingAssistantID }) {
                chatTabs[chatIndex].messages.insert(assistantMessage, at: pendingIndex)
            } else {
                chatTabs[chatIndex].messages.append(assistantMessage)
            }
            messageIDsByItem[update.itemID] = assistantMessage.id
            chatStreamingAssistantMessageIDsByIdentifier[identifier] = messageIDsByItem
        }

        ensurePendingAssistantPlaceholder(
            identifier: identifier,
            pendingAssistantID: pendingAssistantID,
            metadata: metadata
        )

        if activeChatTabId != identifier {
            // Background chat tabs still accumulate full streamed content in model state,
            // but skip per-delta UI rendering work until the tab is visible again.
            scheduleChatStreamingCheckpointPersist(identifier: identifier)
            return
        }
        refreshChatTabView(chatIndex: chatIndex)
    }

    private func ensurePendingAssistantPlaceholder(
        identifier: String,
        pendingAssistantID: UUID,
        metadata: (modelId: String?, reasoningLevel: String?)
    ) {
        guard chatRequestTasksByIdentifier[identifier] != nil else { return }
        guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        guard !chatTabs[chatIndex].messages.contains(where: { $0.id == pendingAssistantID }) else { return }

        let pendingAssistant = PersistedChatMessage(
            id: pendingAssistantID,
            role: .assistant,
            text: Self.chatLoadingPlaceholder,
            modelId: metadata.modelId,
            reasoningLevel: metadata.reasoningLevel
        )
        chatTabs[chatIndex].messages.append(pendingAssistant)
        chatPendingAssistantMessageIDsByIdentifier[identifier] = pendingAssistantID
    }

    private func setPendingAssistantMessage(identifier: String, pendingAssistantID: UUID, text: String) {
        guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }),
              let messageIndex = chatTabs[chatIndex].messages.firstIndex(where: { $0.id == pendingAssistantID }) else {
            return
        }
        guard chatTabs[chatIndex].messages[messageIndex].text != text else { return }
        chatTabs[chatIndex].messages[messageIndex].text = text
        persistChatTabs()
        if activeChatTabId == identifier {
            refreshChatTabView(chatIndex: chatIndex)
        }
    }

    private func normalizeFinalAssistantMessage(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeCodexSteerStreamIfNeeded(
        identifier: String,
        agentType: AgentType
    ) -> AsyncStream<String>? {
        guard agentType == .codex else {
            chatSteerInputContinuationsByIdentifier[identifier]?.finish()
            chatSteerInputContinuationsByIdentifier.removeValue(forKey: identifier)
            return nil
        }
        chatSteerInputContinuationsByIdentifier[identifier]?.finish()
        chatSteerInputContinuationsByIdentifier.removeValue(forKey: identifier)

        return AsyncStream<String> { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            self.chatSteerInputContinuationsByIdentifier[identifier] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.chatSteerInputContinuationsByIdentifier.removeValue(forKey: identifier)
                }
            }
        }
    }

    private func handleChatSlashCommandIfNeeded(identifier: String, chatIndex: Int, text: String) -> Bool {
        guard text.hasPrefix("/") else { return false }
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let rawCommand = parts.first else { return false }
        let command = rawCommand.lowercased()
        let args = Array(parts.dropFirst())
        let agentType = chatTabs[chatIndex].agentType

        switch command {
        case "/clear":
            cancelInFlightChatRequest(identifier: identifier)
            chatTabs[chatIndex].messages.removeAll()
            chatTabs[chatIndex].conversationSessionID = nil
            persistChatTabs()
            refreshChatTabView(chatIndex: chatIndex)
            return true
        case "/model":
            return applyChatSlashModelCommand(identifier: identifier, chatIndex: chatIndex, args: args)
        case "/effort":
            return applyChatSlashEffortCommand(identifier: identifier, chatIndex: chatIndex, args: args)
        case "/help":
            appendChatSlashHelpMessage(chatIndex: chatIndex)
            return true
        default:
            if agentType == .codex {
                appendChatAssistantMessage(
                    identifier: identifier,
                    text: "Codex chat supports /help, /clear, /model, and /effort."
                )
                return true
            }
            return false
        }
    }

    private func appendChatSlashHelpMessage(chatIndex: Int) {
        let agentType = chatTabs[chatIndex].agentType
        let commands: [String]
        switch agentType {
        case .codex:
            commands = ["/help", "/clear", "/model <id>", "/effort <low|medium|high>"]
        case .claude:
            commands = ["/help", "/clear", "/model <id>", "/effort <low|medium|high>"]
        case .custom:
            commands = ["/clear"]
        }

        let body = "Available slash commands:\n" + commands.map { "• \($0)" }.joined(separator: "\n")
        let metadata = chatMessageMetadata(for: chatIndex)
        let assistant = PersistedChatMessage(
            role: .assistant,
            text: body,
            modelId: metadata.modelId,
            reasoningLevel: metadata.reasoningLevel
        )
        chatTabs[chatIndex].messages.append(assistant)
        persistChatTabs()
        refreshChatTabView(chatIndex: chatIndex)
    }

    private func applyChatSlashModelCommand(identifier: String, chatIndex: Int, args: [String]) -> Bool {
        let agentType = chatTabs[chatIndex].agentType
        guard agentType != .custom else { return false }
        guard let requestedModel = args.first?.trimmingCharacters(in: .whitespacesAndNewlines), !requestedModel.isEmpty else {
            if let modelId = chatTabs[chatIndex].modelId {
                appendChatAssistantMessage(identifier: identifier, text: "Current model: \(modelId)")
            } else {
                appendChatAssistantMessage(identifier: identifier, text: "No model selected.")
            }
            return true
        }

        guard let validatedModelId = AgentModelsService.shared.validatedModelId(requestedModel, for: agentType) else {
            appendChatAssistantMessage(identifier: identifier, text: "Unknown model: \(requestedModel)")
            return true
        }

        let validatedEffort = AgentModelsService.shared.validatedReasoningLevel(
            chatTabs[chatIndex].reasoningLevel,
            for: agentType,
            modelId: validatedModelId
        )
        chatTabs[chatIndex].modelId = validatedModelId
        chatTabs[chatIndex].reasoningLevel = validatedEffort
        AgentLastSelectionStore.saveModel(validatedModelId, for: agentType)
        if let validatedEffort {
            AgentLastSelectionStore.saveReasoning(validatedEffort, for: agentType, modelId: validatedModelId)
        }
        persistChatTabs()
        refreshChatTabView(chatIndex: chatIndex)
        appendChatAssistantMessage(identifier: identifier, text: "Model changed to \(validatedModelId).")
        return true
    }

    private func applyChatSlashEffortCommand(identifier: String, chatIndex: Int, args: [String]) -> Bool {
        let agentType = chatTabs[chatIndex].agentType
        guard agentType != .custom else { return false }
        guard let requestedEffort = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !requestedEffort.isEmpty else {
            if let currentEffort = chatTabs[chatIndex].reasoningLevel {
                appendChatAssistantMessage(identifier: identifier, text: "Current reasoning effort: \(currentEffort).")
            } else {
                appendChatAssistantMessage(identifier: identifier, text: "No reasoning effort selected.")
            }
            return true
        }

        guard let validatedEffort = AgentModelsService.shared.validatedReasoningLevel(
            requestedEffort,
            for: agentType,
            modelId: chatTabs[chatIndex].modelId
        ) else {
            appendChatAssistantMessage(identifier: identifier, text: "Unsupported reasoning effort: \(requestedEffort)")
            return true
        }

        chatTabs[chatIndex].reasoningLevel = validatedEffort
        AgentLastSelectionStore.saveReasoning(
            validatedEffort,
            for: agentType,
            modelId: chatTabs[chatIndex].modelId
        )
        persistChatTabs()
        refreshChatTabView(chatIndex: chatIndex)
        appendChatAssistantMessage(identifier: identifier, text: "Reasoning effort set to \(validatedEffort).")
        return true
    }

    private func appendChatAssistantMessage(identifier: String, text: String) {
        guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        let metadata = chatMessageMetadata(for: chatIndex)
        let assistant = PersistedChatMessage(
            role: .assistant,
            text: text,
            modelId: metadata.modelId,
            reasoningLevel: metadata.reasoningLevel
        )
        chatTabs[chatIndex].messages.append(assistant)
        persistChatTabs()
        refreshChatTabView(chatIndex: chatIndex)
    }

    private func chatModelDisplayName(for chatIndex: Int, modelId: String?) -> String? {
        guard chatTabs.indices.contains(chatIndex), let modelId, !modelId.isEmpty else { return modelId }
        let agentType = chatTabs[chatIndex].agentType
        return AgentModelsService.shared.config(for: agentType)?.models.first(where: { $0.id == modelId })?.label ?? modelId
    }

    private func chatMessageMetadata(for chatIndex: Int) -> (modelId: String?, reasoningLevel: String?) {
        guard chatTabs.indices.contains(chatIndex) else { return (nil, nil) }
        let entry = chatTabs[chatIndex]
        guard entry.agentType != .custom else {
            return (entry.modelId, entry.reasoningLevel)
        }

        let normalizedModelId = AgentModelsService.shared.validatedModelId(entry.modelId, for: entry.agentType) ?? entry.modelId
        let normalizedReasoning = AgentModelsService.shared.validatedReasoningLevel(
            entry.reasoningLevel,
            for: entry.agentType,
            modelId: normalizedModelId
        ) ?? entry.reasoningLevel
        return (normalizedModelId, normalizedReasoning)
    }

    private func normalizeAttachmentsForSubmission(_ attachments: [PersistedChatAttachment]) -> [PersistedChatAttachment] {
        var seen: Set<String> = []
        var normalized: [PersistedChatAttachment] = []
        for attachment in attachments {
            let normalizedPath = URL(fileURLWithPath: attachment.filePath).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: normalizedPath) else { continue }
            guard !seen.contains(normalizedPath) else { continue }
            seen.insert(normalizedPath)
            normalized.append(
                PersistedChatAttachment(
                    id: attachment.id,
                    filePath: normalizedPath,
                    kind: attachment.kind
                )
            )
        }
        return normalized
    }

    private func prepareAttachmentsForAgentSubmission(
        _ attachments: [PersistedChatAttachment],
        worktreePath: String
    ) -> [PersistedChatAttachment] {
        let normalizedWorktree = URL(fileURLWithPath: worktreePath).standardizedFileURL
        let worktreePrefix = normalizedWorktree.path.hasSuffix("/")
            ? normalizedWorktree.path
            : normalizedWorktree.path + "/"
        let stagingDirectory = normalizedWorktree
            .appendingPathComponent(".magent", isDirectory: true)
            .appendingPathComponent("chat-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        var prepared: [PersistedChatAttachment] = []
        for attachment in attachments {
            let sourceURL = URL(fileURLWithPath: attachment.filePath).standardizedFileURL
            let sourcePath = sourceURL.path
            guard FileManager.default.fileExists(atPath: sourcePath) else { continue }

            if sourcePath == normalizedWorktree.path || sourcePath.hasPrefix(worktreePrefix) {
                prepared.append(attachment)
                continue
            }

            do {
                try FileManager.default.createDirectory(
                    at: stagingDirectory,
                    withIntermediateDirectories: true
                )
                let destinationURL = uniqueAttachmentDestination(
                    in: stagingDirectory,
                    preferredFilename: sourceURL.lastPathComponent
                )
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                prepared.append(
                    PersistedChatAttachment(
                        id: attachment.id,
                        filePath: destinationURL.standardizedFileURL.path,
                        kind: attachment.kind
                    )
                )
            } catch {
                prepared.append(attachment)
            }
        }
        return normalizeAttachmentsForSubmission(prepared)
    }

    private func uniqueAttachmentDestination(in directory: URL, preferredFilename: String) -> URL {
        let fallbackName = "attachment"
        let rawName = preferredFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = (rawName.isEmpty ? fallbackName : rawName)
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: "-")
        let candidate = directory.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let nsName = safeName as NSString
        let base = nsName.deletingPathExtension.isEmpty ? fallbackName : nsName.deletingPathExtension
        let ext = nsName.pathExtension
        for index in 2...999 {
            let filename = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let url = directory.appendingPathComponent(filename)
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
    }

    private func agentChatAttachments(from attachments: [PersistedChatAttachment]) -> [AgentChatAttachment] {
        attachments.map { attachment in
            let kind: AgentChatAttachment.Kind
            switch attachment.kind {
            case .file:
                kind = .file
            case .image:
                kind = .image
            case .video:
                kind = .video
            }
            return AgentChatAttachment(path: attachment.filePath, kind: kind)
        }
    }

    private func persistChatTabs() {
        thread.persistedChatTabs = chatTabs.map { entry in
            PersistedChatTab(
                identifier: entry.identifier,
                agentType: entry.agentType,
                title: entry.title,
                messages: entry.messages,
                draftInput: entry.draftInput,
                draftAttachments: entry.draftAttachments,
                conversationSessionID: entry.conversationSessionID,
                modelId: entry.modelId,
                reasoningLevel: entry.reasoningLevel,
                isPinned: entry.isPinned
            )
        }
        threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: thread.persistedChatTabs)
    }

    private func scheduleChatStreamingCheckpointPersist(identifier: String) {
        chatStreamingCheckpointTasksByIdentifier[identifier]?.cancel()
        chatStreamingCheckpointTasksByIdentifier[identifier] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s trailing-edge throttle
            await MainActor.run {
                guard let self else { return }
                guard self.chatRequestTasksByIdentifier[identifier] != nil else {
                    self.chatStreamingCheckpointTasksByIdentifier.removeValue(forKey: identifier)
                    return
                }
                self.persistChatTabs()
                self.chatStreamingCheckpointTasksByIdentifier.removeValue(forKey: identifier)
            }
        }
    }

    private func updateChatDraftInput(identifier: String, draftInput: String) {
        guard let index = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        guard chatTabs[index].draftInput != draftInput else { return }
        chatTabs[index].draftInput = draftInput
        persistChatTabs()
    }

    private func updateChatDraftAttachments(identifier: String, draftAttachments: [PersistedChatAttachment]) {
        guard let index = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        guard chatTabs[index].draftAttachments != draftAttachments else { return }
        chatTabs[index].draftAttachments = draftAttachments
        persistChatTabs()
    }

    private func updateChatModelReasoning(identifier: String, modelId: String?, reasoningLevel: String?) {
        guard let index = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        guard chatTabs[index].modelId != modelId || chatTabs[index].reasoningLevel != reasoningLevel else { return }
        chatTabs[index].modelId = modelId
        chatTabs[index].reasoningLevel = reasoningLevel
        persistChatTabs()
    }

    private func syncChatModelReasoningFromAgentMessage(chatIndex: Int, output: String) {
        guard chatTabs.indices.contains(chatIndex) else { return }
        let agentType = chatTabs[chatIndex].agentType

        let resolvedModelID: String?
        let resolvedReasoningLevel: String?
        switch agentType {
        case .claude:
            guard let parsed = AgentChatRuntime.parseClaudeModelChange(from: output) else { return }
            let matchedModelID = resolveClaudeModelID(fromModelLabel: parsed.modelLabel)
            resolvedModelID = matchedModelID
            resolvedReasoningLevel = AgentModelsService.shared.validatedReasoningLevel(
                parsed.effortLevel,
                for: .claude,
                modelId: matchedModelID ?? chatTabs[chatIndex].modelId
            )
        case .codex:
            guard let parsed = AgentChatRuntime.parseCodexModelChange(from: output) else { return }
            let validatedModelID = AgentModelsService.shared.validatedModelId(parsed.modelId, for: .codex)
            resolvedModelID = validatedModelID
            resolvedReasoningLevel = AgentModelsService.shared.validatedReasoningLevel(
                parsed.effortLevel,
                for: .codex,
                modelId: validatedModelID ?? chatTabs[chatIndex].modelId
            )
        case .custom:
            return
        }

        if let modelId = resolvedModelID {
            chatTabs[chatIndex].modelId = modelId
            AgentLastSelectionStore.saveModel(modelId, for: agentType)
        }
        if let reasoningLevel = resolvedReasoningLevel {
            chatTabs[chatIndex].reasoningLevel = reasoningLevel
            AgentLastSelectionStore.saveReasoning(reasoningLevel, for: agentType, modelId: chatTabs[chatIndex].modelId)
        }
    }

    private func resolveClaudeModelID(fromModelLabel modelLabel: String) -> String? {
        guard let config = AgentModelsService.shared.config(for: .claude) else { return nil }
        let normalizedTarget = normalizedModelLabelForMatching(modelLabel)
        guard !normalizedTarget.isEmpty else { return nil }

        if let exactMatch = config.models.first(where: { normalizedModelLabelForMatching($0.label) == normalizedTarget }) {
            return exactMatch.id
        }

        if let resolvedLabelMatch = config.models.first(where: {
            let resolved = threadManager.resolvedModelLabel(for: .claude, modelId: $0.id) ?? $0.label
            return normalizedModelLabelForMatching(resolved) == normalizedTarget
        }) {
            return resolvedLabelMatch.id
        }

        if let fuzzyMatch = config.models.first(where: {
            let resolved = threadManager.resolvedModelLabel(for: .claude, modelId: $0.id) ?? $0.label
            let candidate = normalizedModelLabelForMatching(resolved)
            return candidate.contains(normalizedTarget) || normalizedTarget.contains(candidate)
        }) {
            return fuzzyMatch.id
        }

        return nil
    }

    private func normalizedModelLabelForMatching(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined()
    }

    private func chatContinueSubtitle() -> String {
        if thread.isMain {
            return "Thread: Main"
        }
        if let description = thread.taskDescription {
            return "Thread: \(description) (\(thread.branchName))"
        }
        return "Thread: \(thread.branchName)"
    }

    private func chatConversationMarkdown(chatEntry: ChatTabEntry, projectName: String) -> String {
        ContextExporter.formatAsMarkdown(
            rawContent: chatConversationTranscript(chatEntry.messages),
            sourceAgent: chatEntry.agentType,
            threadName: thread.name,
            projectName: projectName
        )
    }

    private func chatConversationTranscript(_ messages: [PersistedChatMessage]) -> String {
        guard !messages.isEmpty else { return "No chat messages yet." }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        var lines: [String] = []
        for message in messages {
            let roleName: String = switch message.role {
            case .user: "User"
            case .assistant: "Assistant"
            case .system: "System"
            }
            let timestamp = formatter.string(from: message.createdAt)
            lines.append("\(roleName) (\(timestamp)):")
            lines.append(message.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func chatExportDefaultFileName(for title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let slug = title
            .lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let base = slug.isEmpty ? "chat-context" : "chat-\(slug)"
        return "\(base).md"
    }
}
