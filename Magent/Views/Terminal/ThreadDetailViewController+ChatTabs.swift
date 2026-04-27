import Cocoa
import MagentCore

extension ThreadDetailViewController {

    // MARK: - Restore (In-memory)

    func restoreChatTabItems() {
        chatTabs = thread.persistedChatTabs.map { persisted in
            ChatTabEntry(
                identifier: persisted.identifier,
                agentType: persisted.agentType,
                title: persisted.title,
                messages: persisted.messages,
                viewController: nil
            )
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
            let vc = ChatTabViewController(identifier: identifier, agentType: entry.agentType, messages: entry.messages)
            vc.onSubmit = { [weak self] text in
                self?.submitChatPrompt(identifier: identifier, text: text)
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

    // MARK: - Messaging

    private func submitChatPrompt(identifier: String, text: String) {
        guard let entryIndex = chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }

        let user = PersistedChatMessage(role: .user, text: text)
        let pendingAssistant = PersistedChatMessage(role: .assistant, text: "Thinking…")
        chatTabs[entryIndex].messages.append(user)
        chatTabs[entryIndex].messages.append(pendingAssistant)
        persistChatTabs()
        chatTabs[entryIndex].viewController?.update(agentType: chatTabs[entryIndex].agentType, messages: chatTabs[entryIndex].messages)

        let contextMessages = chatTabs[entryIndex].messages
        let worktreePath = thread.worktreePath
        let agentType = chatTabs[entryIndex].agentType

        Task {
            let prompt = buildPiPrompt(from: contextMessages)
            let command = "command pi --mode json --no-session \(ShellExecutor.shellQuote(prompt))"
            let result = await ShellExecutor.execute(command, workingDirectory: worktreePath)

            let responseText: String
            if result.exitCode == 0 {
                let parsed = parsePiAssistantText(from: result.stdout)
                responseText = parsed.isEmpty ? "No response from Pi." : parsed
            } else {
                let errorText = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                responseText = errorText.isEmpty
                    ? "Pi chat failed (exit \(result.exitCode))."
                    : "Pi chat failed: \(errorText)"
            }

            await MainActor.run {
                guard let currentIndex = self.chatTabs.firstIndex(where: { $0.identifier == identifier }) else { return }
                guard let messageIndex = self.chatTabs[currentIndex].messages.firstIndex(where: { $0.id == pendingAssistant.id }) else { return }
                self.chatTabs[currentIndex].messages[messageIndex].text = responseText
                self.persistChatTabs()
                self.chatTabs[currentIndex].viewController?.update(agentType: agentType, messages: self.chatTabs[currentIndex].messages)
            }
        }
    }

    private func buildPiPrompt(from messages: [PersistedChatMessage]) -> String {
        let context = messages.suffix(20).map { message in
            let role = message.role == .user ? "User" : "Assistant"
            return "\(role): \(message.text)"
        }.joined(separator: "\n\n")

        return """
        Continue this conversation. Be concise and accurate.

        \(context)
        """
    }

    private func parsePiAssistantText(from stdout: String) -> String {
        var deltas: [String] = []

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let json = object as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            guard type == "message_update" else { continue }
            guard let message = json["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  role == "assistant" else {
                continue
            }

            guard let assistantEvent = json["assistantMessageEvent"] as? [String: Any],
                  let eventType = assistantEvent["type"] as? String,
                  eventType == "text_delta",
                  let delta = assistantEvent["delta"] as? String else {
                continue
            }
            deltas.append(delta)
        }

        return deltas.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persistChatTabs() {
        thread.persistedChatTabs = chatTabs.map { entry in
            PersistedChatTab(
                identifier: entry.identifier,
                agentType: entry.agentType,
                title: entry.title,
                messages: entry.messages
            )
        }
        threadManager.updatePersistedChatTabs(for: thread.id, chatTabs: thread.persistedChatTabs)
    }
}
