import Cocoa
import MagentCore

extension ThreadDetailViewController {
    private static let chatLoadingPlaceholder = "Thinking..."

    // MARK: - Restore (In-memory)

    func restoreChatTabItems() {
        let thinkingPlaceholders: Set<String> = ["Thinking.", "Thinking..", "Thinking...", "Thinking…"]
        var restoredTabsMutated = false
        chatTabs = thread.persistedChatTabs.map { persisted in
            var messages = persisted.messages
            for index in messages.indices {
                guard messages[index].role == .assistant,
                      thinkingPlaceholders.contains(messages[index].text) else {
                    continue
                }
                // Any persisted "Thinking…" placeholder is stale after process relaunch.
                // Convert it to a terminal state so later requests start from clean UI state.
                messages[index].text = "Request cancelled."
                restoredTabsMutated = true
            }
            return ChatTabEntry(
                identifier: persisted.identifier,
                agentType: persisted.agentType,
                title: persisted.title,
                messages: messages,
                draftInput: persisted.draftInput,
                conversationSessionID: persisted.conversationSessionID,
                modelId: persisted.modelId,
                reasoningLevel: persisted.reasoningLevel,
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

            tabItems.append(item)
            tabSlots.append(.chat(identifier: entry.identifier))
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
            conversationSessionID: conversationSessionID,
            modelId: modelId,
            reasoningLevel: reasoningLevel,
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

        dismissLoadingOverlay()

        for (i, item) in tabItems.enumerated() {
            item.isSelected = (i == displayIndex)
        }

        guard let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }

        if chatTabs[entryIndex].viewController == nil {
            let entry = chatTabs[entryIndex]
            let vc = ChatTabViewController(
                identifier: identifier,
                agentType: entry.agentType,
                messages: entry.messages,
                draftInput: entry.draftInput,
                modelId: entry.modelId,
                reasoningLevel: entry.reasoningLevel
            )
            vc.onSubmit = { [weak self] text in
                self?.submitChatPrompt(identifier: identifier, text: text)
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
            vc.onModelReasoningChanged = { [weak self] modelId, reasoningLevel in
                self?.updateChatModelReasoning(identifier: identifier, modelId: modelId, reasoningLevel: reasoningLevel)
            }
            chatTabs[entryIndex].viewController = vc
        }

        guard let vc = chatTabs[entryIndex].viewController else { return }

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
        vc.focusComposer()
        activeChatTabId = identifier
        currentTabIndex = displayIndex
        postFocusedThreadContextChangedIfKeyWindow()

        if thread.lastSelectedTabIdentifier != identifier {
            thread.lastSelectedTabIdentifier = identifier
            threadManager.updateLastSelectedTab(for: thread.id, identifier: identifier)
        }
        UserDefaults.standard.set(thread.id.uuidString, forKey: Self.lastOpenedThreadDefaultsKey)
        UserDefaults.standard.set(identifier, forKey: Self.lastOpenedTabDefaultsKey)

        // Chat is a GUI tab type, not a terminal surface.
        scrollOverlay.isHidden = true
        setScrollFABVisible(false)
        promptTOCCanShowForCurrentTab = false
        applyPromptTOCVisibility()
    }

    func hideActiveChatTab() {
        guard let activeId = activeChatTabId,
              let entry = chatTabs.first(where: { $0.identifier == activeId }) else { return }
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

    private func submitChatPrompt(identifier: String, text: String) {
        guard let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if handleChatSlashCommandIfNeeded(identifier: identifier, chatIndex: entryIndex, text: trimmedText) {
            return
        }
        cancelInFlightChatRequest(identifier: identifier)

        let user = PersistedChatMessage(role: .user, text: trimmedText)
        let pendingAssistant = PersistedChatMessage(role: .assistant, text: Self.chatLoadingPlaceholder)
        chatTabs[entryIndex].messages.append(user)
        chatTabs[entryIndex].messages.append(pendingAssistant)
        chatPendingAssistantMessageIDsByIdentifier[identifier] = pendingAssistant.id
        persistChatTabs()
        chatTabs[entryIndex].viewController?.update(
            agentType: chatTabs[entryIndex].agentType,
            messages: chatTabs[entryIndex].messages,
            draftInput: chatTabs[entryIndex].draftInput,
            modelId: chatTabs[entryIndex].modelId,
            reasoningLevel: chatTabs[entryIndex].reasoningLevel
        )

        let worktreePath = thread.worktreePath
        let agentType = chatTabs[entryIndex].agentType
        let conversationSessionID = chatTabs[entryIndex].conversationSessionID
        let selectedModelId = chatTabs[entryIndex].modelId
        let selectedReasoningLevel = chatTabs[entryIndex].reasoningLevel
        let taskToken = UUID()

        let task = Task { [weak self] in
            guard let self else { return }
            let response = await AgentChatRuntime.execute(
                agentType: agentType,
                prompt: text,
                workingDirectory: worktreePath,
                conversationSessionID: conversationSessionID,
                claudeSystemPrompt: IPCAgentDocs.claudeSystemPrompt,
                modelId: selectedModelId,
                reasoningLevel: selectedReasoningLevel
            )

            await MainActor.run {
                guard self.chatRequestTaskTokensByIdentifier[identifier] == taskToken else { return }
                self.chatRequestTasksByIdentifier.removeValue(forKey: identifier)
                self.chatRequestTaskTokensByIdentifier.removeValue(forKey: identifier)
                self.chatPendingAssistantMessageIDsByIdentifier.removeValue(forKey: identifier)
                guard let currentIndex = self.chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
                guard let messageIndex = self.chatTabs[currentIndex].messages.firstIndex(where: { $0.id == pendingAssistant.id }) else { return }
                self.chatTabs[currentIndex].messages[messageIndex].text = response.assistantText
                self.chatTabs[currentIndex].conversationSessionID = response.conversationSessionID
                self.syncChatModelReasoningFromAgentMessage(chatIndex: currentIndex, output: response.assistantText)
                self.persistChatTabs()
                self.chatTabs[currentIndex].viewController?.update(
                    agentType: agentType,
                    messages: self.chatTabs[currentIndex].messages,
                    draftInput: self.chatTabs[currentIndex].draftInput,
                    modelId: self.chatTabs[currentIndex].modelId,
                    reasoningLevel: self.chatTabs[currentIndex].reasoningLevel
                )
                self.refreshTabStatusIndicators()
            }
        }
        chatRequestTasksByIdentifier[identifier] = task
        chatRequestTaskTokensByIdentifier[identifier] = taskToken
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

        if let pendingMessageID = chatPendingAssistantMessageIDsByIdentifier.removeValue(forKey: identifier),
           let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }),
           let messageIndex = chatTabs[entryIndex].messages.firstIndex(where: { $0.id == pendingMessageID }) {
            chatTabs[entryIndex].messages[messageIndex].text = "Request cancelled."
            persistChatTabs()
            chatTabs[entryIndex].viewController?.update(
                agentType: chatTabs[entryIndex].agentType,
                messages: chatTabs[entryIndex].messages,
                draftInput: chatTabs[entryIndex].draftInput,
                modelId: chatTabs[entryIndex].modelId,
                reasoningLevel: chatTabs[entryIndex].reasoningLevel
            )
        }

        refreshTabStatusIndicators()
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
            chatTabs[chatIndex].viewController?.update(
                agentType: agentType,
                messages: chatTabs[chatIndex].messages,
                draftInput: chatTabs[chatIndex].draftInput,
                modelId: chatTabs[chatIndex].modelId,
                reasoningLevel: chatTabs[chatIndex].reasoningLevel
            )
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
        let assistant = PersistedChatMessage(role: .assistant, text: body)
        chatTabs[chatIndex].messages.append(assistant)
        persistChatTabs()
        chatTabs[chatIndex].viewController?.update(
            agentType: agentType,
            messages: chatTabs[chatIndex].messages,
            draftInput: chatTabs[chatIndex].draftInput,
            modelId: chatTabs[chatIndex].modelId,
            reasoningLevel: chatTabs[chatIndex].reasoningLevel
        )
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
        chatTabs[chatIndex].viewController?.update(
            agentType: agentType,
            messages: chatTabs[chatIndex].messages,
            draftInput: chatTabs[chatIndex].draftInput,
            modelId: chatTabs[chatIndex].modelId,
            reasoningLevel: chatTabs[chatIndex].reasoningLevel
        )
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
        chatTabs[chatIndex].viewController?.update(
            agentType: agentType,
            messages: chatTabs[chatIndex].messages,
            draftInput: chatTabs[chatIndex].draftInput,
            modelId: chatTabs[chatIndex].modelId,
            reasoningLevel: chatTabs[chatIndex].reasoningLevel
        )
        appendChatAssistantMessage(identifier: identifier, text: "Reasoning effort set to \(validatedEffort).")
        return true
    }

    private func appendChatAssistantMessage(identifier: String, text: String) {
        guard let chatIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        let agentType = chatTabs[chatIndex].agentType
        let assistant = PersistedChatMessage(role: .assistant, text: text)
        chatTabs[chatIndex].messages.append(assistant)
        persistChatTabs()
        chatTabs[chatIndex].viewController?.update(
            agentType: agentType,
            messages: chatTabs[chatIndex].messages,
            draftInput: chatTabs[chatIndex].draftInput,
            modelId: chatTabs[chatIndex].modelId,
            reasoningLevel: chatTabs[chatIndex].reasoningLevel
        )
    }

    private func persistChatTabs() {
        thread.persistedChatTabs = chatTabs.map { entry in
            PersistedChatTab(
                identifier: entry.identifier,
                agentType: entry.agentType,
                title: entry.title,
                messages: entry.messages,
                draftInput: entry.draftInput,
                conversationSessionID: entry.conversationSessionID,
                modelId: entry.modelId,
                reasoningLevel: entry.reasoningLevel
            )
        }
        threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: thread.persistedChatTabs)
    }

    private func updateChatDraftInput(identifier: String, draftInput: String) {
        guard let index = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
        guard chatTabs[index].draftInput != draftInput else { return }
        chatTabs[index].draftInput = draftInput
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
