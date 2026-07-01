import Cocoa
import MagentCore

extension ThreadListViewController {

    // MARK: - Actions

    @objc func addThreadForProjectTapped(_ sender: NSButton) {
        guard !isCreatingThread else { return }

        suppressNextProjectRowToggle = true
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.suppressNextProjectRowToggle = false
            }
        }

        guard let project = projectFromProjectHeaderButton(sender) else { return }
        let isOptionPressed = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        if isOptionPressed {
            let resolvedAgent = threadManager.effectiveAgentType(for: project.id)
            let modelId = resolvedAgent.flatMap { AgentLastSelectionStore.lastModel(for: $0) }
            let reasoning = resolvedAgent.flatMap { AgentLastSelectionStore.lastReasoning(for: $0, modelId: modelId) }
            createThread(for: project, requestedAgentType: nil, useAgentCommand: true, modelId: modelId, reasoningLevel: reasoning)
        } else {
            presentNewThreadSheet(for: project, anchorView: sender)
        }
    }

    @objc func openMissingProjectLocation(_ sender: NSButton) {
        guard let projectId = projectId(from: sender),
              let project = persistence.loadSettings().projects.first(where: { $0.id == projectId }) else { return }

        let panel = NSOpenPanel()
        panel.title = "Open Repository Location"
        panel.message = "Choose the new location for \(project.name)."
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: project.repoPath).deletingLastPathComponent()

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self.recoverMissingProject(projectId: projectId, newRepoURL: url)
            }
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    @objc func discardMissingProject(_ sender: NSButton) {
        guard let projectId = projectId(from: sender),
              let project = persistence.loadSettings().projects.first(where: { $0.id == projectId }) else { return }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Discard \(project.name)?"
        alert.informativeText = "This permanently removes the repository, its threads, archived threads, sections, local sync settings, and related Magent metadata from Magent. Files on disk are not deleted."
        alert.addButton(withTitle: "Discard Repository")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        if let window = view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.discardProjectFromMagent(projectId: projectId)
            }
        } else {
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            discardProjectFromMagent(projectId: projectId)
        }
    }

    @objc func toggleSectionExpanded(_ sender: NSButton) {
        suppressNextSectionRowToggle = true
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.suppressNextSectionRowToggle = false
            }
        }

        let row = outlineView.row(for: sender)
        guard row >= 0,
              let section = outlineView.item(atRow: row) as? SidebarSection,
              !section.threads.isEmpty else { return }
        toggleSection(section, animatedDisclosureButton: sender)
    }

    @objc func toggleProjectExpanded(_ sender: NSButton) {
        suppressNextProjectRowToggle = true
        defer {
            DispatchQueue.main.async { [weak self] in
                self?.suppressNextProjectRowToggle = false
            }
        }

        let project: SidebarProject? = {
            if let rawProjectId = sender.objectValue as? String,
               let projectId = UUID(uuidString: rawProjectId),
               let matched = sidebarProjects.first(where: { $0.projectId == projectId }) {
                return matched
            }
            let row = outlineView.row(for: sender)
            guard row >= 0 else { return nil }
            return outlineView.item(atRow: row) as? SidebarProject
        }()
        guard let project else { return }

        let willCollapse = !isProjectCollapsed(project)
        setProjectCollapsed(project, isCollapsed: willCollapse)
        reloadData()
    }

    func toggleSection(_ section: SidebarSection, animatedDisclosureButton: NSButton? = nil) {
        let willCollapse = !isSectionCollapsed(section)
        setSectionCollapsed(section, isCollapsed: willCollapse)

        if let button = animatedDisclosureButton {
            updateSectionDisclosureButton(button, isExpanded: !willCollapse)
        }
        reloadData()
    }

    func updateSectionDisclosureButton(_ button: NSButton, isExpanded: Bool) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        button.title = ""
        button.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.up" : "chevron.down",
            accessibilityDescription: isExpanded ? "Collapse section" : "Expand section"
        )?.withSymbolConfiguration(symbolConfig)
        button.imageScaling = .scaleNone
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(isExpanded ? "Collapse section" : "Expand section")
    }

    func updateProjectDisclosureButton(_ button: NSButton, isExpanded: Bool) {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        button.title = ""
        button.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.up" : "chevron.down",
            accessibilityDescription: isExpanded ? "Collapse project" : "Expand project"
        )?.withSymbolConfiguration(symbolConfig)
        button.imageScaling = .scaleNone
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(isExpanded ? "Collapse project" : "Expand project")
    }

    func sectionDisclosureButton(for section: SidebarSection) -> NSButton? {
        let row = outlineView.row(forItem: section)
        guard row >= 0,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView else { return nil }
        return cell.subviews.first(where: { $0.identifier == Self.sectionDisclosureButtonIdentifier }) as? NSButton
    }

    private func setSectionCollapsed(_ section: SidebarSection, isCollapsed: Bool) {
        var collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedSectionIdsKey) ?? [])
        let key = sectionCollapseStorageKey(section)
        if isCollapsed {
            collapsed.insert(key)
        } else {
            collapsed.remove(key)
        }
        UserDefaults.standard.set(Array(collapsed), forKey: Self.collapsedSectionIdsKey)
    }

    func isSectionCollapsed(_ section: SidebarSection) -> Bool {
        let collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedSectionIdsKey) ?? [])
        return collapsed.contains(sectionCollapseStorageKey(section))
    }

    func isProjectCollapsed(_ project: SidebarProject) -> Bool {
        let collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedProjectIdsKey) ?? [])
        return collapsed.contains(project.projectId.uuidString)
    }

    func setProjectCollapsed(_ project: SidebarProject, isCollapsed: Bool) {
        var collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedProjectIdsKey) ?? [])
        if isCollapsed {
            collapsed.insert(project.projectId.uuidString)
        } else {
            collapsed.remove(project.projectId.uuidString)
        }
        UserDefaults.standard.set(Array(collapsed), forKey: Self.collapsedProjectIdsKey)
    }

    func sectionCollapseStorageKey(_ section: SidebarSection) -> String {
        "\(section.projectId.uuidString):\(section.sectionId.uuidString)"
    }

    private func refreshSectionDisclosureButton(for section: SidebarSection) {
        let row = outlineView.row(forItem: section)
        guard row >= 0,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let button = cell.subviews.first(where: { $0.identifier == Self.sectionDisclosureButtonIdentifier }) as? NSButton else { return }
        updateSectionDisclosureButton(button, isExpanded: !isSectionCollapsed(section))
    }

    func refreshVisibleSectionDisclosureButtons() {
        for row in 0..<outlineView.numberOfRows {
            guard let section = outlineView.item(atRow: row) as? SidebarSection else { continue }
            refreshSectionDisclosureButton(for: section)
        }
    }

    private func projectFromProjectHeaderButton(_ sender: NSButton) -> Project? {
        let settings = persistence.loadSettings()

        if let rawProjectId = sender.objectValue as? String,
           let projectId = UUID(uuidString: rawProjectId),
           let matched = settings.projects.first(where: { $0.id == projectId }) {
            return matched
        }

        let row = outlineView.row(for: sender)
        guard row >= 0,
              let sidebarProject = outlineView.item(atRow: row) as? SidebarProject else { return nil }
        return settings.projects.first(where: { $0.id == sidebarProject.projectId })
    }

    private func projectId(from sender: NSButton) -> UUID? {
        if let raw = sender.objectValue as? String {
            return UUID(uuidString: raw)
        }
        let row = outlineView.row(for: sender)
        guard row >= 0,
              let missing = outlineView.item(atRow: row) as? SidebarMissingProjectRow else { return nil }
        return missing.projectId
    }

    @MainActor
    private func recoverMissingProject(projectId: UUID, newRepoURL: URL) async {
        let newRepoPath = newRepoURL.standardizedFileURL.path
        guard await isGitRepository(at: newRepoPath) else {
            showInvalidRepositoryAlert(path: newRepoPath)
            return
        }

        var settings = persistence.loadSettings()
        guard let projectIndex = settings.projects.firstIndex(where: { $0.id == projectId }) else { return }
        let oldProject = settings.projects[projectIndex]
        let oldRepoPath = URL(fileURLWithPath: oldProject.repoPath).standardizedFileURL.path
        let oldWorktreesBasePath = URL(fileURLWithPath: oldProject.resolvedWorktreesBasePath()).standardizedFileURL.path
        let newWorktreesBasePath = RepositoryRecoveryPlanner.worktreesBasePath(
            oldProject: oldProject,
            newRepoPath: newRepoPath
        )
        let resolvedNewWorktreesBasePath = URL(fileURLWithPath: newWorktreesBasePath.replacingOccurrences(of: "$MAGENT_PROJECT_NAME", with: oldProject.name)).standardizedFileURL.path

        settings.projects[projectIndex].repoPath = newRepoPath
        settings.projects[projectIndex].worktreesBasePath = newWorktreesBasePath

        let originalThreads = persistence.loadThreads()
        var allThreads = originalThreads
        for index in allThreads.indices where allThreads[index].projectId == projectId {
            allThreads[index].worktreePath = RepositoryRecoveryPlanner.remappedThreadWorktreePath(
                allThreads[index].worktreePath,
                oldRepoPath: oldRepoPath,
                newRepoPath: newRepoPath,
                oldWorktreesBasePath: oldWorktreesBasePath,
                newWorktreesBasePath: resolvedNewWorktreesBasePath
            )
        }

        do {
            try persistence.saveThreads(allThreads)
            do {
                try persistence.saveSettings(settings)
            } catch {
                try? persistence.saveThreads(originalThreads)
                throw error
            }
            threadManager.threads = allThreads.filter { !$0.isArchived }
            reloadData()
            NotificationCenter.default.post(name: .magentSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .magentThreadsDidChange, object: nil)
            BannerManager.shared.show(message: "Repository location updated.", style: .info)
        } catch {
            BannerManager.shared.show(message: "Failed to update repository location: \(error.localizedDescription)", style: .error)
        }
    }

    private func isGitRepository(at path: String) async -> Bool {
        let result = await ShellExecutor.execute("git rev-parse --show-toplevel", workingDirectory: path)
        guard result.exitCode == 0 else { return false }
        let topLevel = URL(fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let selectedPath = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return topLevel == selectedPath
    }

    private func showInvalidRepositoryAlert(path: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Not a Git Repository"
        alert.informativeText = "Magent could not open a Git repository at:\n\(path)"
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func discardProjectFromMagent(projectId: UUID) {
        var settings = persistence.loadSettings()
        settings.projects.removeAll { $0.id == projectId }
        let originalThreads = persistence.loadThreads()
        var allThreads = originalThreads
        let removedActiveThreads = threadManager.threads.filter { $0.projectId == projectId }
        let removedSelectedThread = selectedThreadID.flatMap { selectedId in
            removedActiveThreads.first(where: { $0.id == selectedId })
        }
        allThreads.removeAll { $0.projectId == projectId }

        do {
            try persistence.saveThreads(allThreads)
            do {
                try persistence.saveSettings(settings)
            } catch {
                try? persistence.saveThreads(originalThreads)
                throw error
            }
            PopoutWindowManager.shared.closePopouts(forProjectId: projectId)
            threadManager.threads = allThreads.filter { !$0.isArchived }
            if removedSelectedThread != nil {
                clearSelectedThreadState()
            }
            var collapsedProjects = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedProjectIdsKey) ?? [])
            collapsedProjects.remove(projectId.uuidString)
            UserDefaults.standard.set(Array(collapsedProjects), forKey: Self.collapsedProjectIdsKey)
            var collapsedSections = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedSectionIdsKey) ?? [])
            collapsedSections = collapsedSections.filter { !$0.hasPrefix(projectId.uuidString + ":") }
            UserDefaults.standard.set(Array(collapsedSections), forKey: Self.collapsedSectionIdsKey)
            reloadData()
            NotificationCenter.default.post(name: .magentSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .magentThreadsDidChange, object: nil)
            if let removedSelectedThread {
                delegate?.threadList(self, didDeleteThread: removedSelectedThread)
            }
            Task {
                await ThreadManager.shared.cleanupStaleMagentSessions(minimumStaleAge: 0)
            }
        } catch {
            BannerManager.shared.show(message: "Failed to discard repository: \(error.localizedDescription)", style: .error)
        }
    }

    private func showNoProjectsAlert() {
        let alert = NSAlert()
        alert.messageText = "No Projects"
        alert.informativeText = "Add a project in Settings first."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func preferredProjectForQuickCreate(
        from projects: [Project],
        contextThread: MagentThread? = nil
    ) -> Project? {
        guard !projects.isEmpty else { return nil }

        if let selectedThread = contextThread ?? selectedThreadFromState(),
           let matched = projects.first(where: { $0.id == selectedThread.projectId }) {
            return matched
        }

        let selectedRow = outlineView.selectedRow
        if selectedRow >= 0 {
            if let selectedProject = outlineView.item(atRow: selectedRow) as? SidebarProject,
               let matched = projects.first(where: { $0.id == selectedProject.projectId }) {
                return matched
            }
        }

        if let lastProjectRaw = UserDefaults.standard.string(forKey: Self.lastOpenedProjectDefaultsKey),
           let lastProjectId = UUID(uuidString: lastProjectRaw),
           let matched = projects.first(where: { $0.id == lastProjectId }) {
            return matched
        }

        if let firstSidebarProject = sidebarProjects.first,
           let matched = projects.first(where: { $0.id == firstSidebarProject.projectId }) {
            return matched
        }

        return projects.first
    }

    func presentNewThreadSheet(
        for project: Project,
        anchorView: NSView,
        presentingWindow: NSWindow? = nil,
        baseBranch: String? = nil,
        sourceThread: MagentThread? = nil,
        selectedSectionIdOverride: UUID? = nil,
        recoveryPrefill: AgentLaunchSheetPrefill? = nil
    ) {
        guard let window = presentingWindow ?? view.window else { return }
        let settings = persistence.loadSettings()

        var autoHintParts: [String] = []
        if settings.autoRenameBranches { autoHintParts.append("branch") }
        if settings.autoSetThreadDescription { autoHintParts.append("description") }
        let autoGenerateHint: String? = autoHintParts.isEmpty ? nil : {
            let joined = autoHintParts.joined(separator: " and ")
            let cap = joined.prefix(1).uppercased() + joined.dropFirst()
            return "\(cap) will be auto-generated from the first prompt if left blank."
        }()

        let injection = threadManager.effectiveInjection(for: project.id)

        // Build per-project section data for the section picker.
        var sectionsByProjectId: [UUID: [ThreadSection]] = [:]
        var defaultSectionIdByProjectId: [UUID: UUID] = [:]
        for p in settings.projects {
            if settings.shouldUseThreadSections(for: p.id) {
                let visible = settings.visibleSections(for: p.id)
                if !visible.isEmpty {
                    sectionsByProjectId[p.id] = visible
                }
            }
            if let defaultId = settings.defaultSection(for: p.id)?.id {
                defaultSectionIdByProjectId[p.id] = defaultId
            }
        }

        // When creating from an existing thread, pre-select its section.
        if let sourceThread, let sourceSectionId = threadManager.effectiveSectionId(for: sourceThread, settings: settings) {
            defaultSectionIdByProjectId[sourceThread.projectId] = sourceSectionId
        }
        if let selectedSectionIdOverride {
            defaultSectionIdByProjectId[project.id] = selectedSectionIdOverride
        }

        let defaultBranchName = project.defaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only prefill the base branch field when explicitly creating from another thread's branch.
        // When nil, the field stays empty and uses the default branch placeholder.
        let resolvedBaseBranchPrefill: String? = baseBranch

        let isFork = sourceThread != nil && baseBranch != nil
        let sheetTitle = isFork ? "Fork Thread" : "New Thread"
        let sheetSubtitle: String? = {
            guard isFork, let src = sourceThread else { return nil }
            if src.isMain {
                return "Thread: Main"
            }
            if let desc = src.taskDescription {
                return "Thread: \(desc) (\(src.branchName))"
            }
            return "Thread: \(src.branchName)"
        }()

        let config = AgentLaunchSheetConfig(
            title: sheetTitle,
            acceptButtonTitle: "Create Thread",
            draftScope: .newThread(projectId: project.id),
            availableAgents: settings.availableActiveAgents,
            defaultAgentType: threadManager.effectiveAgentType(for: project.id),
            subtitle: sheetSubtitle,
            availableProjects: isFork ? [project] : settings.projects,
            showDescriptionAndBranchFields: true,
            autoGenerateHint: autoGenerateHint,
            terminalInjectionPrefill: injection.terminalCommand.isEmpty ? nil : injection.terminalCommand,
            agentContextPrefill: injection.agentContext.isEmpty ? nil : injection.agentContext,
            recoveryPrefill: recoveryPrefill,
            sectionsByProjectId: sectionsByProjectId,
            defaultSectionIdByProjectId: defaultSectionIdByProjectId,
            baseBranchPrefill: resolvedBaseBranchPrefill,
            baseBranchRepoPath: project.repoPath,
            defaultBranchName: defaultBranchName,
            showDraftCheckbox: true
        )
        let capturedSourceThread = sourceThread
        let controller = AgentLaunchPromptSheetController(config: config)
        controller.present(for: window) { [weak self] result in
            guard let self, let result else { return }
            let targetProject = result.selectedProject ?? project

            // Insert after the source thread when in the same project, section, and
            // sidebar group. When the source is pinned, place at the top of the visible
            // group instead (right below pinned threads).
            let effectiveInsertAfter: UUID?
            let insertAtTop: Bool
            if let source = capturedSourceThread, targetProject.id == source.projectId {
                let settings = self.persistence.loadSettings()
                let sourceSectionId = self.threadManager.effectiveSectionId(for: source, settings: settings)
                let sameSection = sourceSectionId == result.selectedSectionId
                if source.sidebarListState == .visible && sameSection {
                    effectiveInsertAfter = source.id
                    insertAtTop = false
                } else if source.sidebarListState == .pinned && sameSection {
                    effectiveInsertAfter = nil
                    insertAtTop = true
                } else {
                    effectiveInsertAfter = nil
                    insertAtTop = false
                }
            } else {
                effectiveInsertAfter = nil
                insertAtTop = false
            }

            self.createThread(
                for: targetProject,
                requestedAgentType: result.agentType,
                useAgentCommand: (result.isDraft || result.agentSurface == .chat) ? false : result.useAgentCommand,
                sourceThread: capturedSourceThread,
                baseBranch: result.baseBranch,
                initialPrompt: (result.isDraft || result.agentSurface == .chat) ? nil : result.prompt,
                shouldSubmitInitialPrompt: !result.isDraft && result.agentSurface != .chat,
                taskDescription: result.description,
                requestedBranchName: result.branchName,
                pendingPromptFileURL: result.pendingPromptFileURL,
                requestedSectionId: result.selectedSectionId,
                insertAfterThreadId: effectiveInsertAfter,
                insertAtTopOfVisibleGroup: insertAtTop,
                initialWebURL: result.initialWebURL,
                initialChatTab: {
                    guard result.agentSurface == .chat,
                          let agentType = result.agentType else { return nil }
                    return PersistedChatTab(
                        identifier: "chat:\(UUID().uuidString)",
                        agentType: agentType,
                        title: "\(agentType.displayName) Chat",
                        messages: [],
                        draftInput: result.prompt ?? "",
                        modelId: result.modelId,
                        reasoningLevel: result.reasoningLevel
                    )
                }(),
                draftPrompt: result.isDraft ? result.agentType.map { ($0, result.prompt ?? "", result.modelId, result.reasoningLevel) } : nil,
                modelId: result.modelId,
                reasoningLevel: result.reasoningLevel,
                localFileSyncEntriesOverride: isFork ? capturedSourceThread?.localFileSyncEntriesSnapshot : nil
            )
        }
    }

    func buildAgentSubmenu(for project: Project, extraData: [String: String] = [:]) -> NSMenu {
        let settings = persistence.loadSettings()
        let activeAgents = settings.availableActiveAgents
        var representedData = extraData
        representedData["projectId"] = project.id.uuidString

        let submenu = NSMenu()
        AgentMenuBuilder.populate(
            menu: submenu,
            menuTitle: "New Thread in \(project.name)",
            defaultAgentType: threadManager.effectiveAgentType(for: project.id),
            activeAgents: activeAgents,
            includeChatOption: settings.isChatsFeatureEnabled,
            target: self,
            action: #selector(projectAgentMenuItemSelected(_:)),
            extraData: representedData
        )
        return submenu
    }

    @objc private func projectAgentMenuItemSelected(_ sender: NSMenuItem) {
        guard let selection = AgentMenuBuilder.parseSelection(from: sender),
              let projectIdRaw = selection.data["projectId"],
              let projectId = UUID(uuidString: projectIdRaw) else { return }

        let settings = persistence.loadSettings()
        guard let project = settings.projects.first(where: { $0.id == projectId }) else { return }

        let baseBranch = selection.data["baseBranch"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch selection.mode {
        case .terminal:
            createThread(for: project, requestedAgentType: nil, useAgentCommand: false, baseBranch: baseBranch)
        case .agent(let agentType):
            let modelId = AgentLastSelectionStore.lastModel(for: agentType)
            let reasoning = AgentLastSelectionStore.lastReasoning(for: agentType, modelId: modelId)
            createThread(for: project, requestedAgentType: agentType, useAgentCommand: true, baseBranch: baseBranch, modelId: modelId, reasoningLevel: reasoning)
        case .chat(let agentType):
            let modelId = AgentLastSelectionStore.lastModel(for: agentType)
            let reasoning = AgentLastSelectionStore.lastReasoning(for: agentType, modelId: modelId)
            createThread(
                for: project,
                requestedAgentType: agentType,
                useAgentCommand: false,
                baseBranch: baseBranch,
                initialChatTab: PersistedChatTab(
                    identifier: "chat:\(UUID().uuidString)",
                    agentType: agentType,
                    title: "\(agentType.displayName) Chat",
                    messages: [],
                    modelId: modelId,
                    reasoningLevel: reasoning
                ),
                modelId: modelId,
                reasoningLevel: reasoning
            )
        case .projectDefault:
            let resolvedAgent = threadManager.effectiveAgentType(for: project.id)
            let modelId = resolvedAgent.flatMap { AgentLastSelectionStore.lastModel(for: $0) }
            let reasoning = resolvedAgent.flatMap { AgentLastSelectionStore.lastReasoning(for: $0, modelId: modelId) }
            createThread(for: project, requestedAgentType: nil, useAgentCommand: true, baseBranch: baseBranch, modelId: modelId, reasoningLevel: reasoning)
        case .web:
            presentNewThreadSheet(for: project, anchorView: outlineView)
        }
    }

    /// Called from SplitViewController's Cmd+Shift+N shortcut. Creates a new thread
    /// branching from the currently selected thread's branch, inheriting its section
    /// and inserting right below it in the sidebar.
    func requestNewThreadFromBranch(
        contextThread: MagentThread? = nil,
        presentingWindow: NSWindow? = nil
    ) {
        guard !isCreatingThread else { return }

        let settings = persistence.loadSettings()
        guard let sourceThread = contextThread ?? selectedThreadFromState(),
              let project = settings.projects.first(where: { $0.id == sourceThread.projectId }),
              let baseBranch = baseBranchForNewThread(from: sourceThread, project: project) else {
            // Fall back to regular new-thread flow when no thread is selected or no branch is available.
            requestNewThread(contextThread: contextThread, presentingWindow: presentingWindow)
            return
        }

        presentNewThreadSheet(
            for: project,
            anchorView: outlineView,
            presentingWindow: presentingWindow,
            baseBranch: baseBranch,
            sourceThread: sourceThread
        )
    }

    /// Called from SplitViewController's Cmd+N shortcut to respect the loading guard.
    /// Picks the most relevant project context and opens that project's agent menu.
    /// When a thread is selected, inherits its section and positions the new thread below it.
    func requestNewThread(
        contextThread: MagentThread? = nil,
        presentingWindow: NSWindow? = nil
    ) {
        guard !isCreatingThread else { return }

        let settings = persistence.loadSettings()
        let projects = settings.projects
        guard !projects.isEmpty else {
            showNoProjectsAlert()
            return
        }
        guard let project = preferredProjectForQuickCreate(from: projects, contextThread: contextThread) else { return }

        // Use the selected thread as the source for section/position inheritance.
        let selectedSource = contextThread ?? selectedThreadFromState()
        let sourceInSameProject = selectedSource?.projectId == project.id ? selectedSource : nil

        let isOptionPressed = NSApp.currentEvent?.modifierFlags.contains(.option) == true
        if isOptionPressed {
            let isPinnedSource = sourceInSameProject?.sidebarListState == .pinned
            let resolvedAgent = threadManager.effectiveAgentType(for: project.id)
            let modelId = resolvedAgent.flatMap { AgentLastSelectionStore.lastModel(for: $0) }
            let reasoning = resolvedAgent.flatMap { AgentLastSelectionStore.lastReasoning(for: $0, modelId: modelId) }
            createThread(
                for: project,
                requestedAgentType: nil,
                useAgentCommand: true,
                requestedSectionId: sourceInSameProject?.sectionId,
                insertAfterThreadId: isPinnedSource ? nil : sourceInSameProject?.id,
                insertAtTopOfVisibleGroup: isPinnedSource,
                modelId: modelId,
                reasoningLevel: reasoning
            )
        } else {
            presentNewThreadSheet(
                for: project,
                anchorView: outlineView,
                presentingWindow: presentingWindow,
                sourceThread: sourceInSameProject
            )
        }
    }

    func createThread(
        for project: Project,
        requestedAgentType: AgentType? = nil,
        useAgentCommand: Bool = true,
        sourceThread: MagentThread? = nil,
        baseBranch: String? = nil,
        initialPrompt: String? = nil,
        shouldSubmitInitialPrompt: Bool = true,
        taskDescription: String? = nil,
        requestedBranchName: String? = nil,
        pendingPromptFileURL: URL? = nil,
        requestedSectionId: UUID? = nil,
        insertAfterThreadId: UUID? = nil,
        insertAtTopOfVisibleGroup: Bool = false,
        initialWebURL: URL? = nil,
        initialChatTab: PersistedChatTab? = nil,
        draftPrompt: (agentType: AgentType, prompt: String, modelId: String?, reasoningLevel: String?)? = nil,
        modelId: String? = nil,
        reasoningLevel: String? = nil,
        localFileSyncEntriesOverride: [LocalFileSyncEntry]? = nil
    ) {
        isCreatingThread = true
        refreshVisibleProjectAddButtonsEnabledState()

        Task {
            do {
                let created = try await self.threadManager.createThread(
                    project: project,
                    requestedAgentType: requestedAgentType,
                    useAgentCommand: useAgentCommand,
                    initialPrompt: initialPrompt,
                    shouldSubmitInitialPrompt: shouldSubmitInitialPrompt,
                    initialDraftTab: draftPrompt.map { draftPrompt in
                        PersistedDraftTab(
                            identifier: "draft:\(UUID().uuidString)",
                            agentType: draftPrompt.agentType,
                            prompt: draftPrompt.prompt,
                            modelId: draftPrompt.modelId,
                            reasoningLevel: draftPrompt.reasoningLevel
                        )
                    },
                    initialChatTab: initialChatTab,
                    requestedBranchName: requestedBranchName,
                    requestedBaseBranch: baseBranch,
                    pendingPromptFileURL: pendingPromptFileURL,
                    requestedSectionId: requestedSectionId,
                    insertAfterThreadId: insertAfterThreadId,
                    insertAtTopOfVisibleGroup: insertAtTopOfVisibleGroup,
                    initialWebURL: initialWebURL,
                    modelId: modelId,
                    reasoningLevel: reasoningLevel,
                    localFileSyncEntriesOverride: localFileSyncEntriesOverride
                )
                if let desc = taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !desc.isEmpty {
                    try? self.threadManager.setTaskDescription(threadId: created.id, description: desc)
                }
                // Unblock the + button as soon as the thread exists — the rename
                // below is a background nicety that shouldn't gate new-thread creation.
                await MainActor.run {
                    self.isCreatingThread = false
                    self.refreshVisibleProjectAddButtonsEnabledState()

                    // Expand the section if it's collapsed
                    let settings = self.persistence.loadSettings()
                    let effectiveSectionId = requestedSectionId ?? settings.defaultSection(for: project.id)?.id
                    if let sectionId = effectiveSectionId {
                        let section = self.sidebarProjects
                            .flatMap { $0.children }
                            .compactMap { $0 as? SidebarSection }
                            .first { $0.sectionId == sectionId }
                        if let section, self.isSectionCollapsed(section) {
                            self.setSectionCollapsed(section, isCollapsed: false)
                            self.reloadData()
                        }
                    }
                }
                // Trigger auto-rename from the draft prompt text after the draft-only
                // thread has been created and persisted.
                if let draftPrompt {
                    let trimmedPrompt = draftPrompt.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedPrompt.isEmpty {
                        _ = await self.threadManager.autoRenameThreadFromDraftPromptIfNeeded(
                            threadId: created.id,
                            prompt: trimmedPrompt
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    self.isCreatingThread = false
                    self.refreshVisibleProjectAddButtonsEnabledState()
                    let recoveryPrefill = self.failedThreadCreationRecoveryPrefill(
                        requestedAgentType: requestedAgentType,
                        useAgentCommand: useAgentCommand,
                        initialPrompt: initialPrompt,
                        taskDescription: taskDescription,
                        requestedBranchName: requestedBranchName,
                        initialWebURL: initialWebURL,
                        draftPrompt: draftPrompt,
                        modelId: modelId,
                        reasoningLevel: reasoningLevel
                    )
                    let recoverablePrompt = recoveryPrefill?.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    BannerManager.shared.show(
                        message: "Failed to create thread: \(error.localizedDescription)",
                        style: .error,
                        duration: nil,
                        actions: [
                            BannerAction(title: "Reopen") { [weak self] in
                                guard let self else { return }
                                BannerManager.shared.dismissCurrent()
                                self.presentNewThreadSheet(
                                    for: project,
                                    anchorView: self.outlineView,
                                    baseBranch: baseBranch,
                                    sourceThread: sourceThread,
                                    selectedSectionIdOverride: requestedSectionId,
                                    recoveryPrefill: recoveryPrefill
                                )
                            },
                            BannerAction(title: "Copy Prompt") {
                                guard let recoverablePrompt,
                                      !recoverablePrompt.isEmpty else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(recoverablePrompt, forType: .string)
                            }
                        ]
                    )
                }
            }
        }
    }

    private func refreshVisibleProjectAddButtonsEnabledState() {
        refreshStickyProjectAddButtonEnabledState()

        for row in 0..<outlineView.numberOfRows {
            guard outlineView.item(atRow: row) is SidebarProject,
                  let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
                  let addButton = cell.subviews.first(where: { $0.identifier == Self.projectAddButtonIdentifier }) as? NSButton
            else { continue }
            addButton.isEnabled = !isCreatingThread
        }
    }

    private func failedThreadCreationRecoveryPrefill(
        requestedAgentType: AgentType?,
        useAgentCommand: Bool,
        initialPrompt: String?,
        taskDescription: String?,
        requestedBranchName: String?,
        initialWebURL: URL?,
        draftPrompt: (agentType: AgentType, prompt: String, modelId: String?, reasoningLevel: String?)?,
        modelId: String?,
        reasoningLevel: String?
    ) -> AgentLaunchSheetPrefill? {
        let prompt: String
        let agentType: AgentType?
        let selectionRaw: String?
        let isDraft: Bool

        if let initialWebURL {
            prompt = initialWebURL.absoluteString
            agentType = nil
            selectionRaw = "web"
            isDraft = false
        } else if let draftPrompt {
            prompt = draftPrompt.prompt
            agentType = draftPrompt.agentType
            selectionRaw = draftPrompt.agentType.rawValue
            isDraft = true
        } else if useAgentCommand {
            prompt = initialPrompt ?? ""
            agentType = requestedAgentType
            selectionRaw = requestedAgentType?.rawValue
            isDraft = false
        } else {
            prompt = initialPrompt ?? ""
            agentType = nil
            selectionRaw = "terminal"
            isDraft = false
        }

        let description = (selectionRaw == "web" || selectionRaw == "terminal") ? nil : taskDescription
        let branchName = (selectionRaw == "web" || selectionRaw == "terminal") ? nil : requestedBranchName
        let hasRecoverableContent =
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !(description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            !(branchName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            modelId != nil ||
            reasoningLevel != nil ||
            selectionRaw != nil ||
            isDraft
        guard hasRecoverableContent else { return nil }

        return AgentLaunchSheetPrefill(
            prompt: prompt,
            description: description,
            branchName: branchName,
            agentType: agentType,
            modelId: draftPrompt?.modelId ?? modelId,
            reasoningLevel: draftPrompt?.reasoningLevel ?? reasoningLevel,
            selectionRaw: selectionRaw,
            isDraft: isDraft
        )
    }

    // MARK: - Pending Prompt Recovery

    /// Called once on first appearance. Scans `/tmp` for any unsubmitted prompt files
    /// left behind by a previous crash and surfaces a banner for each one so the user
    /// can reopen the creation sheet with all fields pre-populated.
    func checkForPendingPromptRecovery() {
        let pending = PendingInitialPromptStore.loadAll()
        guard !pending.isEmpty else { return }

        // .newTab entries are stored on ThreadManager for per-thread banners;
        // only .newThread entries show as global BannerManager banners.
        let bannerCount = pending.filter { $0.prompt.scopeKind == .newThread }.count

        // Show banners sequentially — when the user acts on or dismisses one, the next appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showNextRecoveryBanner(pending: pending, index: 0, bannerTotal: bannerCount, bannerShown: 0)
        }
    }

    private func showNextRecoveryBanner(
        pending: [(url: URL, prompt: PendingInitialPrompt)],
        index: Int,
        bannerTotal: Int,
        bannerShown: Int
    ) {
        guard index < pending.count else { return }
        let (url, record) = pending[index]
        let settings = persistence.loadSettings()
        let bannerIndex = bannerShown + 1
        let countSuffix = bannerTotal > 1 ? " (\(bannerIndex) of \(bannerTotal))" : ""

        let next = { [weak self] in
            self?.showNextRecoveryBanner(pending: pending, index: index + 1, bannerTotal: bannerTotal, bannerShown: bannerShown)
        }
        let nextAfterBanner = { [weak self] in
            self?.showNextRecoveryBanner(pending: pending, index: index + 1, bannerTotal: bannerTotal, bannerShown: bannerIndex)
        }

        switch record.scopeKind {
        case .newThread:
            guard let projectId = record.projectId,
                  let project = settings.projects.first(where: { $0.id == projectId }) else {
                try? FileManager.default.removeItem(at: url)
                next()
                return
            }
            let prefill = AgentLaunchSheetPrefill(
                prompt: record.prompt,
                description: record.description,
                branchName: record.branchName,
                agentType: record.agentType,
                modelId: record.modelId,
                reasoningLevel: record.reasoningLevel,
                selectionRaw: record.selectionRaw,
                isDraft: false
            )
            let promptPreview = record.prompt.magentPromptPreview(maxLength: 140, singleLine: true)
            let promptDetails = record.prompt.magentPromptPreview(maxLength: 500, singleLine: false)
            BannerManager.shared.show(
                message: "Unsubmitted thread prompt recovered — Project: \(project.name)\(countSuffix)\nPreview: \(promptPreview)",
                style: .warning,
                duration: nil,
                isDismissible: true,
                actions: [
                    BannerAction(title: "Copy Prompt") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.prompt, forType: .string)
                    },
                    BannerAction(title: "Reopen") { [weak self] in
                        BannerManager.shared.dismissCurrent()
                        // File stays alive; a new pending file will be created on next submit.
                        // Delete original once the recovery sheet is closed (submitted or cancelled).
                        self?.presentRecoverySheet(for: project, originalPendingURL: url, prefill: prefill)
                        nextAfterBanner()
                    },
                    BannerAction(title: "Discard") {
                        BannerManager.shared.dismissCurrent()
                        try? FileManager.default.removeItem(at: url)
                        nextAfterBanner()
                    }
                ],
                details: promptDetails,
                detailsCollapsedTitle: "Show More",
                detailsExpandedTitle: "Hide More"
            )

        case .newTab:
            guard let threadId = record.threadId,
                  let thread = threadManager.threads.first(where: { $0.id == threadId }),
                  let project = settings.projects.first(where: { $0.id == thread.projectId }) else {
                try? FileManager.default.removeItem(at: url)
                next()
                return
            }
            // Store on ThreadManager — ThreadDetailViewController shows a per-thread banner
            // when the user selects this thread, instead of a global BannerManager banner.
            threadManager.addPendingPromptRecovery(
                for: threadId,
                info: ThreadManager.PendingPromptRecoveryInfo(
                    tempFileURL: url,
                    prompt: record.prompt,
                    agentType: record.agentType,
                    projectId: project.id,
                    modelId: record.modelId,
                    reasoningLevel: record.reasoningLevel
                )
            )
            next()
        }
    }

    /// Opens a new-thread creation sheet pre-populated with `prefill`.
    /// Deletes `originalPendingURL` when the sheet is closed (whether submitted or cancelled).
    private func presentRecoverySheet(
        for project: Project,
        originalPendingURL: URL,
        prefill: AgentLaunchSheetPrefill
    ) {
        guard let window = view.window else { return }
        let settings = persistence.loadSettings()
        let config = AgentLaunchSheetConfig(
            title: "New Thread",
            acceptButtonTitle: "Create Thread",
            draftScope: .newThread(projectId: project.id),
            availableAgents: settings.availableActiveAgents,
            defaultAgentType: threadManager.effectiveAgentType(for: project.id),
            subtitle: nil,
            showDescriptionAndBranchFields: true,
            autoGenerateHint: nil,
            terminalInjectionPrefill: nil,
            agentContextPrefill: nil,
            recoveryPrefill: prefill
        )
        let controller = AgentLaunchPromptSheetController(config: config)
        controller.present(for: window) { [weak self] result in
            // Delete original recovery file — user has seen and acted on it.
            try? FileManager.default.removeItem(at: originalPendingURL)
            guard let self, let result else { return }
            self.createThread(
                for: project,
                requestedAgentType: result.agentType,
                useAgentCommand: result.useAgentCommand,
                initialPrompt: result.prompt,
                shouldSubmitInitialPrompt: true,
                taskDescription: result.description,
                requestedBranchName: result.branchName,
                pendingPromptFileURL: result.pendingPromptFileURL,
                modelId: result.modelId,
                reasoningLevel: result.reasoningLevel
            )
        }
    }

    // MARK: - Recovery Reopen (from ThreadDetailViewController)

    @objc func handleRecoveryReopenRequested(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let projectId = userInfo["projectId"] as? UUID,
              let tempFileURL = userInfo["tempFileURL"] as? URL,
              let prefill = userInfo["prefill"] as? AgentLaunchSheetPrefill else {
            return
        }
        let settings = persistence.loadSettings()
        guard let project = settings.projects.first(where: { $0.id == projectId }) else { return }
        presentRecoverySheet(for: project, originalPendingURL: tempFileURL, prefill: prefill)
    }

    // MARK: - Add Repository

    @objc func addRepoButtonTapped(_ sender: NSButton) {
        let menu = NSMenu()
        let createItem = NSMenuItem(
            title: String(localized: .AppStrings.repositoryCreateNewMenuItem),
            action: #selector(addRepoCreateNew(_:)),
            keyEquivalent: ""
        )
        createItem.target = self
        createItem.image = NSImage(systemSymbolName: "plus.rectangle.on.folder", accessibilityDescription: nil)

        let importItem = NSMenuItem(
            title: String(localized: .AppStrings.repositoryImportExistingMenuItem),
            action: #selector(addRepoImportExisting(_:)),
            keyEquivalent: ""
        )
        importItem.target = self
        importItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)

        let cloneItem = NSMenuItem(
            title: String(localized: .AppStrings.repositoryCloneMenuItem),
            action: #selector(addRepoClone(_:)),
            keyEquivalent: ""
        )
        cloneItem.target = self
        cloneItem.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)

        menu.addItem(createItem)
        menu.addItem(importItem)
        menu.addItem(cloneItem)

        let anchorView: NSView = sender.window == nil ? view : sender
        let anchorBounds = anchorView.bounds
        menu.popUp(
            positioning: menu.items.first,
            at: NSPoint(x: anchorBounds.minX, y: anchorBounds.maxY + 4),
            in: anchorView
        )
    }

    @objc private func addRepoCreateNew(_ sender: NSMenuItem) {
        presentCreateNewRepositoryFlow()
    }

    @objc private func addRepoImportExisting(_ sender: NSMenuItem) {
        presentImportExistingRepositoryFlow()
    }

    @objc private func addRepoClone(_ sender: NSMenuItem) {
        presentCloneRepositoryFlow()
    }

    func presentCreateNewRepositoryFlow() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = String(localized: .AppStrings.repositoryCreateNewPanelMessage)
        panel.prompt = String(localized: .AppStrings.repositoryCreateNewPanelPrompt)

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let path = url.path

            // Reject folders that already contain a .git directory.
            let gitDir = url.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir.path) {
                let alert = NSAlert()
                alert.messageText = String(localized: .AppStrings.repositoryAlreadyGitRepositoryTitle)
                alert.informativeText = String(localized: .AppStrings.repositoryAlreadyGitRepositoryMessage)
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: .CommonStrings.commonOk))
                alert.beginSheetModal(for: window)
                return
            }

            BannerManager.shared.show(
                message: String(localized: .AppStrings.repositoryCreatingBanner(url.lastPathComponent)),
                style: .info,
                duration: nil,
                isDismissible: false,
                showsSpinner: true
            )

            Task {
                do {
                    try await self.runGit(arguments: ["init", path])

                    // Create an initial empty commit so the default branch actually
                    // exists — without this, worktree creation and branch validation
                    // fail because `git init` alone leaves the repo with no commits
                    // and no materialized branch.
                    try await self.runGit(arguments: [
                        "-C", path,
                        "-c", "user.name=Magent",
                        "-c", "user.email=magent@local.invalid",
                        "-c", "commit.gpgsign=false",
                        "commit", "--allow-empty", "--no-verify", "-m", "Initial commit"
                    ])

                    let defaultBranch = await GitService.shared.detectDefaultBranch(repoPath: path)

                    await MainActor.run {
                        do {
                            try self.addProjectAtPath(url: url, defaultBranch: defaultBranch)
                            BannerManager.shared.show(
                                message: String(localized: .AppStrings.repositoryCreatedBanner(url.lastPathComponent)),
                                style: .info,
                                duration: 3.0
                            )
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "Failed to Add Repository"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: String(localized: .CommonStrings.commonOk))
                            alert.beginSheetModal(for: window)
                        }
                    }
                } catch {
                    await MainActor.run {
                        BannerManager.shared.show(
                            message: String(localized: .AppStrings.repositoryCreateFailedBanner(url.lastPathComponent)),
                            style: .error,
                            duration: 6.0
                        )
                        let alert = NSAlert()
                        alert.messageText = String(localized: .AppStrings.repositoryCreateFailedTitle)
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: String(localized: .CommonStrings.commonOk))
                        alert.beginSheetModal(for: window)
                    }
                }
            }
        }
    }

    func presentImportExistingRepositoryFlow() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: .ConfigurationStrings.configurationSelectRepositoryFolder)

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let path = url.path

            Task {
                let isRepo = await GitService.shared.isGitRepository(at: path)
                let defaultBranch = isRepo ? await GitService.shared.detectDefaultBranch(repoPath: path) : nil
                await MainActor.run {
                    if isRepo {
                        do {
                            try self.addProjectAtPath(url: url, defaultBranch: defaultBranch)
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "Failed to Import Repository"
                            alert.informativeText = error.localizedDescription
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: String(localized: .CommonStrings.commonOk))
                            alert.beginSheetModal(for: window)
                        }
                    } else {
                        let alert = NSAlert()
                        alert.messageText = String(localized: .ConfigurationStrings.configurationAlertNotGitRepositoryTitle)
                        alert.informativeText = String(localized: .ConfigurationStrings.configurationAlertNotGitRepositoryMessage)
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: String(localized: .CommonStrings.commonOk))
                        alert.beginSheetModal(for: window)
                    }
                }
            }
        }
    }

    func presentCloneRepositoryFlow() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: .AppStrings.repositoryCloneAlertTitle)
        alert.informativeText = String(localized: .AppStrings.repositoryCloneAlertMessage)
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: .CommonStrings.commonNext))
        alert.addButton(withTitle: String(localized: .CommonStrings.commonCancel))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        textField.placeholderString = String(localized: .AppStrings.repositoryCloneURLPlaceholder)
        alert.accessoryView = textField

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let remoteURL = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !remoteURL.isEmpty else {
                self.showRepositoryAlert(
                    title: String(localized: .AppStrings.repositoryCloneMissingURLTitle),
                    message: String(localized: .AppStrings.repositoryCloneMissingURLMessage),
                    style: .warning,
                    window: window
                )
                return
            }
            self.presentCloneDestinationPicker(remoteURL: remoteURL, window: window)
        }
    }

    private func presentCloneDestinationPicker(remoteURL: String, window: NSWindow) {
        guard let directoryName = RepositoryCloneDestination.suggestedDirectoryName(from: remoteURL) else {
            showRepositoryAlert(
                title: String(localized: .AppStrings.repositoryCloneInvalidURLTitle),
                message: String(localized: .AppStrings.repositoryCloneInvalidURLMessage),
                style: .warning,
                window: window
            )
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = String(localized: .AppStrings.repositoryCloneParentPanelMessage)
        panel.prompt = String(localized: .AppStrings.repositoryCloneParentPanelPrompt)

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let parentURL = panel.url else { return }
            let destinationURL = parentURL.appendingPathComponent(directoryName, isDirectory: true)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                self.showRepositoryAlert(
                    title: String(localized: .AppStrings.repositoryCloneDestinationExistsTitle),
                    message: String(localized: .AppStrings.repositoryCloneDestinationExistsMessage(destinationURL.path)),
                    style: .warning,
                    window: window
                )
                return
            }

            BannerManager.shared.show(
                message: String(localized: .AppStrings.repositoryCloningBanner(directoryName)),
                style: .info,
                duration: nil,
                isDismissible: false,
                showsSpinner: true
            )

            Task {
                do {
                    try await self.runGit(arguments: ["clone", remoteURL, destinationURL.path])
                    let defaultBranch = await GitService.shared.detectDefaultBranch(repoPath: destinationURL.path)

                    await MainActor.run {
                        do {
                            try self.addProjectAtPath(url: destinationURL, defaultBranch: defaultBranch)
                            BannerManager.shared.show(
                                message: String(localized: .AppStrings.repositoryClonedBanner(directoryName)),
                                style: .info,
                                duration: 3.0
                            )
                        } catch {
                            self.showRepositoryAlert(
                                title: String(localized: .AppStrings.repositoryCloneFailedTitle),
                                message: error.localizedDescription,
                                style: .critical,
                                window: window
                            )
                        }
                    }
                } catch {
                    await MainActor.run {
                        BannerManager.shared.show(
                            message: String(localized: .AppStrings.repositoryCloneFailedBanner(directoryName)),
                            style: .error,
                            duration: 6.0
                        )
                        self.showRepositoryAlert(
                            title: String(localized: .AppStrings.repositoryCloneFailedTitle),
                            message: error.localizedDescription,
                            style: .critical,
                            window: window
                        )
                    }
                }
            }
        }
    }

    private func addProjectAtPath(url: URL, defaultBranch: String?) throws {
        var settings = persistence.loadSettings()

        // Don't add a project that's already registered.
        let path = url.standardizedFileURL.path
        if settings.projects.contains(where: {
            ($0.repoPath as NSString).standardizingPath == (path as NSString).standardizingPath
        }) {
            BannerManager.shared.show(
                message: String(localized: .AppStrings.repositoryAlreadyAddedBanner(url.lastPathComponent)),
                style: .info,
                duration: 4.0
            )
            return
        }

        let project = Project(
            name: url.lastPathComponent,
            repoPath: path,
            worktreesBasePath: Project.suggestedWorktreesPath(for: path),
            defaultBranch: defaultBranch
        )
        settings.projects.append(project)
        try persistence.saveSettings(settings)
        reloadData()

        Task { try? await ThreadManager.shared.createMainThread(project: project) }
    }

    private nonisolated func runGit(arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    cont.resume()
                    return
                }

                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = stderrText?.isEmpty == false
                    ? stderrText!
                    : "git \(arguments.joined(separator: " ")) exited with status \(proc.terminationStatus)"
                cont.resume(throwing: NSError(
                    domain: "Magent",
                    code: Int(proc.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: message]
                ))
            }
            do {
                try process.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    private func showRepositoryAlert(title: String, message: String, style: NSAlert.Style, window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: String(localized: .CommonStrings.commonOk))
        alert.beginSheetModal(for: window)
    }

    // MARK: - Helpers


    // MARK: - Diff Panel

    func refreshDiffPanelForSelectedThread() {
        guard let thread = diffInspectionThreadFromState() else {
            diffPanelView.clearContextThreadIndicator()
            diffPanelView.clear()
            branchMismatchView.clear()
            return
        }
        refreshDiffPanel(for: thread)
    }

    func refreshDiffPanelContextForSelectedThread() {
        guard let thread = diffInspectionThreadFromState() else {
            diffPanelView.clearContextThreadIndicator()
            diffPanelView.updateBranchInfo(branchName: nil, baseBranch: nil, upstreamStatus: nil)
            return
        }
        refreshDiffPanelContext(for: thread)
    }

    func manuallyRefreshSelectedThreadGitState() {
        guard let thread = diffInspectionThreadFromState() else { return }
        if isDiffPanelManualRefreshInFlight {
            pendingDiffPanelManualRefresh = true
            return
        }

        let threadId = thread.id
        isDiffPanelManualRefreshInFlight = true
        pendingDiffPanelManualRefresh = false
        diffPanelView.setRefreshInProgress(true)
        refreshDiffPanel(for: thread, resetPagination: false, preserveSelection: true)

        Task { [weak self] in
            guard let self else { return }

            await self.threadManager.refreshBranchStates()
            await self.threadManager.refreshDirtyStates()
            await self.threadManager.refreshDeliveredStates()

            await MainActor.run {
                let shouldRefreshAgain = self.pendingDiffPanelManualRefresh
                self.pendingDiffPanelManualRefresh = false
                defer {
                    self.isDiffPanelManualRefreshInFlight = false
                    self.diffPanelView.setRefreshInProgress(false)
                }

                guard let contextThread = self.diffInspectionThreadFromState(),
                      contextThread.id == threadId else { return }
                self.refreshDiffPanel(for: contextThread, resetPagination: false, preserveSelection: true)

                if shouldRefreshAgain {
                    DispatchQueue.main.async { [weak self] in
                        self?.manuallyRefreshSelectedThreadGitState()
                    }
                }
            }
        }
    }

    func loadMoreCommitsForSelectedThread() {
        guard let thread = diffInspectionThreadFromState() else { return }
        let nextLimit = diffPanelCommitLimitByThreadId[thread.id, default: diffPanelCommitPageSize] + diffPanelCommitPageSize
        diffPanelCommitLimitByThreadId[thread.id] = nextLimit
        refreshDiffPanel(for: thread, resetPagination: false, preserveSelection: true)
    }

    func handleCommitSelected(_ commitHash: String?) {
        guard let commitHash else {
            // "Uncommitted" selected — CHANGES tab already has working-tree entries; nothing to load
            return
        }
        guard let thread = diffInspectionThreadFromState() else { return }
        let worktreePath = thread.worktreePath
        Task {
            let entries = await GitService.shared.commitDiffStats(worktreePath: worktreePath, commitHash: commitHash)
            await MainActor.run {
                guard (self.diffInspectionThreadID ?? self.selectedThreadID) == thread.id else { return }
                self.diffPanelView.updateCommitEntries(hash: commitHash, entries: entries, subject: "")
            }
        }
    }

    func refreshDiffPanelContext(for thread: MagentThread) {
        let current = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
        let branchName = current.actualBranch ?? current.branchName
        let baseBranch = current.isMain ? nil : threadManager.resolveBaseBranch(for: current)
        Task {
            let upstreamStatus = await GitService.shared.upstreamTrackingStatus(worktreePath: current.worktreePath)
            await MainActor.run {
                guard (self.diffInspectionThreadID ?? self.selectedThreadID) == current.id else { return }
                guard let latest = self.threadManager.threads.first(where: { $0.id == current.id }) else { return }
                let latestBranchName = latest.actualBranch ?? latest.branchName
                let latestBaseBranch = latest.isMain ? nil : self.threadManager.resolveBaseBranch(for: latest)
                guard latestBranchName == branchName,
                      latestBaseBranch == baseBranch else { return }
                self.updateDiffContextThreadIndicator(for: latest)
                self.diffPanelView.updateBranchInfo(
                    branchName: branchName,
                    baseBranch: baseBranch,
                    upstreamStatus: upstreamStatus
                )
            }
        }
    }

    func showBaseBranchMenu(anchorView: NSView) {
        guard let thread = diffInspectionThreadFromState(), !thread.isMain else { return }
        let currentBase = threadManager.resolveBaseBranch(for: thread)
        let threadId = thread.id

        Task { @MainActor in
            let ancestors = await threadManager.listAncestorBranches(for: threadId)
            let menu = NSMenu()
            menu.autoenablesItems = false

            // Build the list: reversed so closest ancestors are at the bottom
            // (menu pops upward from the bottom-left anchor).
            var addedBranches = Set<String>()
            for branch in ancestors.reversed() {
                let displayName = branch.hasPrefix("origin/") ? String(branch.dropFirst(7)) : branch
                let item = NSMenuItem(title: displayName, action: #selector(self.baseBranchMenuItemSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = branch
                if branch == currentBase {
                    item.state = .on
                }
                menu.addItem(item)
                addedBranches.insert(branch)
            }

            // If the current base isn't in the ancestor list (manual override or stale), add it at top
            if !addedBranches.contains(currentBase) {
                let displayName = currentBase.hasPrefix("origin/") ? String(currentBase.dropFirst(7)) : currentBase
                let item = NSMenuItem(title: displayName, action: #selector(self.baseBranchMenuItemSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = currentBase
                item.state = .on
                menu.insertItem(item, at: 0)
            }

            if menu.items.isEmpty {
                let item = NSMenuItem(title: "No ancestor branches found", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
            let otherItem = NSMenuItem(title: "Other…", action: #selector(self.baseBranchOtherSelected(_:)), keyEquivalent: "")
            otherItem.target = self
            otherItem.representedObject = threadId
            menu.addItem(otherItem)

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchorView.bounds.height), in: anchorView)
        }
    }

    @objc private func baseBranchMenuItemSelected(_ sender: NSMenuItem) {
        guard let branch = sender.representedObject as? String,
              let thread = diffInspectionThreadFromState() else { return }
        threadManager.setBaseBranch(branch, for: thread.id)
        refreshDiffPanel(for: thread)
    }

    @objc private func baseBranchOtherSelected(_ sender: NSMenuItem) {
        guard let threadId = sender.representedObject as? UUID,
              let thread = threadManager.threads.first(where: { $0.id == threadId }) else { return }
        let currentBase = threadManager.resolveBaseBranch(for: thread)

        Task { @MainActor in
            // Fetch all branches for combo box suggestions
            let repoPath = thread.worktreePath
            let localBranches = await GitService.shared.listBranchesByDate(repoPath: repoPath)
            let remoteBranches = await GitService.shared.listRemoteBranchesByDate(repoPath: repoPath)

            // Merge local + remote (strip origin/ for display), deduplicate, preserve order
            var seen = Set<String>()
            var allBranches: [String] = []
            for branch in localBranches {
                if seen.insert(branch).inserted {
                    allBranches.append(branch)
                }
            }
            for branch in remoteBranches {
                let name = branch.hasPrefix("origin/") ? String(branch.dropFirst(7)) : branch
                if seen.insert(name).inserted {
                    allBranches.append(name)
                }
            }

            let alert = NSAlert()
            alert.messageText = "Set Target Branch"
            alert.informativeText = "Type a branch name or choose from the list:"
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let comboBox = NSComboBox(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
            comboBox.isEditable = true
            comboBox.completes = true
            comboBox.stringValue = currentBase.hasPrefix("origin/") ? String(currentBase.dropFirst(7)) : currentBase
            comboBox.addItems(withObjectValues: allBranches)
            comboBox.numberOfVisibleItems = 12
            alert.accessoryView = comboBox

            // Make combo box first responder so user can type immediately
            alert.window.initialFirstResponder = comboBox

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }

            let entered = comboBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entered.isEmpty else { return }

            threadManager.setBaseBranch(entered, for: thread.id)
            refreshDiffPanel(for: thread)
        }
    }

    func refreshDiffPanel(for thread: MagentThread, resetPagination: Bool = true, preserveSelection: Bool = false) {
        if resetPagination || diffPanelCommitLimitByThreadId[thread.id] == nil {
            diffPanelCommitLimitByThreadId[thread.id] = diffPanelCommitPageSize
        }
        let commitLimit = diffPanelCommitLimitByThreadId[thread.id] ?? diffPanelCommitPageSize

        // Increment the generation for this thread. The task captures this value and
        // abandons its result if a newer call has since arrived — preventing a slow
        // no-preserve task (spawned at thread selection) from overwriting the result
        // of a faster preserve task (spawned by a background structural reload).
        let generation = (diffPanelRefreshGeneration[thread.id] ?? 0) + 1
        diffPanelRefreshGeneration[thread.id] = generation

        Task {
            let current = self.threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
            let entries: [FileDiffEntry]
            let allBranchEntries: [FileDiffEntry]?
            let commits: [BranchCommit]
            let hasMoreCommits: Bool
            let baseBranch: String?
            let upstreamStatus: BranchUpstreamStatus
            let diffFingerprint: String
            let diffTabFileCount: Int

            if current.isMain {
                baseBranch = nil
                async let entriesTask = GitService.shared.workingTreeDiffStats(worktreePath: current.worktreePath)
                async let commitsTask = GitService.shared.recentCommitLog(
                    worktreePath: current.worktreePath,
                    limit: commitLimit + 1
                )
                async let upstreamTask = GitService.shared.upstreamTrackingStatus(worktreePath: current.worktreePath)
                async let fingerprintTask = GitService.shared.diffFingerprint(
                    worktreePath: current.worktreePath,
                    baseBranch: nil
                )
                entries = await entriesTask
                allBranchEntries = entries // main thread: all changes = uncommitted
                let commitPage = await commitsTask
                hasMoreCommits = commitPage.count > commitLimit
                commits = Array(commitPage.prefix(commitLimit))
                upstreamStatus = await upstreamTask
                diffFingerprint = await fingerprintTask
                diffTabFileCount = entries.count
            } else {
                let resolvedBaseBranch = self.threadManager.resolveBaseBranch(for: current)
                baseBranch = resolvedBaseBranch
                async let entriesTask = GitService.shared.workingTreeDiffStats(worktreePath: current.worktreePath)
                async let diffTabEntriesTask = GitService.shared.threadDiffTabStats(
                    worktreePath: current.worktreePath,
                    baseBranch: resolvedBaseBranch
                )
                async let commitsTask = GitService.shared.commitLog(
                    worktreePath: current.worktreePath,
                    baseBranch: resolvedBaseBranch,
                    limit: commitLimit + 1
                )
                async let upstreamTask = GitService.shared.upstreamTrackingStatus(worktreePath: current.worktreePath)
                async let fingerprintTask = GitService.shared.diffFingerprint(
                    worktreePath: current.worktreePath,
                    baseBranch: resolvedBaseBranch
                )
                entries = await entriesTask
                allBranchEntries = nil
                let commitPage = await commitsTask
                hasMoreCommits = commitPage.count > commitLimit
                commits = Array(commitPage.prefix(commitLimit))
                upstreamStatus = await upstreamTask
                diffFingerprint = await fingerprintTask
                let diffTabEntries = await diffTabEntriesTask
                diffTabFileCount = diffTabEntries.count
            }

            await MainActor.run {
                guard (self.diffInspectionThreadID ?? self.selectedThreadID) == current.id else { return }
                // Discard stale results: a newer refresh call was made after this task was spawned.
                guard (self.diffPanelRefreshGeneration[current.id] ?? 0) == generation else { return }
                self.threadManager.updateCurrentDiffFingerprint(
                    for: current.id,
                    fingerprint: diffTabFileCount > 0 ? diffFingerprint : nil
                )
                NotificationCenter.default.post(
                    name: .magentDiffFileCountChanged,
                    object: nil,
                    userInfo: [
                        "threadId": current.id,
                        "fileCount": diffTabFileCount,
                    ]
                )
                self.updateDiffContextThreadIndicator(for: current)
                self.diffPanelView.update(
                    with: entries,
                    allBranchEntries: allBranchEntries,
                    commits: commits,
                    hasMoreCommits: hasMoreCommits,
                    forceVisible: true,
                    worktreePath: current.worktreePath,
                    branchName: current.actualBranch ?? current.branchName,
                    baseBranch: baseBranch,
                    upstreamStatus: upstreamStatus,
                    threadId: current.id,
                    preserveSelection: preserveSelection
                )
            }
        }
        refreshBranchMismatchView(for: thread)
    }

    func loadAllChangesForSelectedThread() {
        guard let thread = diffInspectionThreadFromState() else { return }
        guard !thread.isMain else { return }

        let generation = diffPanelRefreshGeneration[thread.id] ?? 0
        Task {
            let current = self.threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
            let baseBranch = self.threadManager.resolveBaseBranch(for: current)
            let entries = await GitService.shared.diffStats(
                worktreePath: current.worktreePath,
                baseBranch: baseBranch
            )

            await MainActor.run {
                guard (self.diffInspectionThreadID ?? self.selectedThreadID) == current.id else { return }
                guard (self.diffPanelRefreshGeneration[current.id] ?? 0) == generation else { return }
                self.diffPanelView.updateAllBranchEntries(entries)
            }
        }
    }

    // MARK: - Commit Detail Mode

    func handleCommitDoubleTapped(_ commitHash: String?, title: String) {
        guard let thread = diffInspectionThreadFromState() else { return }
        let worktreePath = thread.worktreePath
        Task {
            let entries: [FileDiffEntry]
            if let hash = commitHash {
                entries = await GitService.shared.commitDiffStats(worktreePath: worktreePath, commitHash: hash)
            } else {
                entries = await GitService.shared.workingTreeDiffStats(worktreePath: worktreePath)
            }
            await MainActor.run {
                guard (self.diffInspectionThreadID ?? self.selectedThreadID) == thread.id else { return }
                self.diffPanelView.enterCommitDetailMode(hash: commitHash, title: title, entries: entries)
                var userInfo: [String: Any] = [
                    "threadId": thread.id,
                    "commitTitle": title,
                ]
                if let commitHash {
                    userInfo["commitHash"] = commitHash
                } else {
                    userInfo["mode"] = "uncommitted"
                }
                NotificationCenter.default.post(name: .magentShowDiffViewer, object: nil, userInfo: userInfo)
            }
        }
    }

    private func updateDiffContextThreadIndicator(for thread: MagentThread) {
        let hasAnyPopoutWindow = !PopoutWindowManager.shared.poppedOutThreadIds.isEmpty
            || !PopoutWindowManager.shared.detachedSessionNames.isEmpty
        guard hasAnyPopoutWindow else {
            diffPanelView.clearContextThreadIndicator()
            return
        }
        let name = thread.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = (name?.isEmpty == false ? name! : thread.name)
        let suffix = isDiffInspectionPopoutContext ? " (Pop-out)" : " (Main)"
        diffPanelView.setContextThreadIndicator("\(displayName)\(suffix)", isPopout: isDiffInspectionPopoutContext)
    }

    // MARK: - Branch Mismatch

    func refreshBranchMismatchView(for thread: MagentThread) {
        // Read the latest transient state from the thread manager
        guard let current = threadManager.threads.first(where: { $0.id == thread.id }) else {
            branchMismatchView.clear()
            return
        }

        // Show branch mismatch (actual != expected) for main and non-main threads
        if current.hasBranchMismatch,
           let actual = current.actualBranch,
           let expected = current.expectedBranch {
            branchMismatchView.update(
                actualBranch: actual,
                expectedBranch: expected,
                hasMismatch: true
            )
            branchMismatchView.onAcceptBranch = { [weak self] in
                self?.handleAcceptBranch(for: current)
            }
            branchMismatchView.onSwitchBranch = { [weak self] in
                self?.handleSwitchBranch(for: current)
            }
            return
        }

        // Non-main threads: show PR target mismatch (app base != PR target)
        if !current.isMain,
           let prInfo = current.pullRequestInfo,
           let prTarget = prInfo.baseBranch,
           !prInfo.isMerged, !prInfo.isClosed {
            let appBase = threadManager.resolveBaseBranch(for: current)
            // Compare without origin/ prefix for matching
            let normalizedAppBase = appBase.hasPrefix("origin/")
                ? String(appBase.dropFirst("origin/".count)) : appBase
            if normalizedAppBase != prTarget {
                branchMismatchView.updatePRTargetMismatch(
                    appBase: appBase,
                    prTarget: prTarget,
                    prLabel: prInfo.displayLabel
                )
                branchMismatchView.onUsePRTarget = { [weak self] in
                    self?.handleUsePRTarget(for: current, prTarget: prTarget)
                }
                return
            }
        }

        // Show one-time banner if the base branch was auto-reset because it no longer exists.
        if let reset = threadManager.baseBranchResets[current.id] {
            let shortOld = reset.oldBase.hasPrefix("origin/")
                ? String(reset.oldBase.dropFirst("origin/".count)) : reset.oldBase
            let shortNew = reset.newBase.hasPrefix("origin/")
                ? String(reset.newBase.dropFirst("origin/".count)) : reset.newBase
            BannerManager.shared.show(
                message: "Base branch \(shortOld) no longer exists — reset to \(shortNew)",
                style: .warning,
                duration: nil,
                isDismissible: true
            )
            threadManager.clearBaseBranchReset(for: current.id)
        }

        branchMismatchView.clear()
    }

    private func handleAcceptBranch(for thread: MagentThread) {
        let actual = thread.actualBranch ?? thread.branchName
        threadManager.acceptActualBranch(threadId: thread.id)
        BannerManager.shared.show(message: "Branch \(actual) accepted as expected", style: .info, duration: 3)
        branchMismatchView.clear()
        refreshDiffPanelForSelectedThread()
    }

    private func handleUsePRTarget(for thread: MagentThread, prTarget: String) {
        // Store as "origin/<branch>" to match the detection format
        let baseBranch = "origin/\(prTarget)"
        threadManager.setBaseBranch(baseBranch, for: thread.id)
        BannerManager.shared.show(
            message: "Target branch changed to \(prTarget)",
            style: .info,
            duration: 3
        )
        branchMismatchView.clear()
        refreshDiffPanelForSelectedThread()
    }

    private func handleSwitchBranch(for thread: MagentThread) {
        Task {
            do {
                try await threadManager.switchToExpectedBranch(threadId: thread.id)
                let expected = threadManager.resolveExpectedBranch(for: thread) ?? thread.branchName
                await MainActor.run {
                    BannerManager.shared.show(message: "Switched back to \(expected)", style: .info, duration: 3)
                    self.branchMismatchView.clear()
                    self.refreshDiffPanelForSelectedThread()
                }
            } catch {
                await MainActor.run {
                    let message: String
                    if let shellError = error as? ShellError,
                       case .commandFailed(_, let stderr) = shellError {
                        let gitMessage = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                        message = gitMessage.isEmpty ? error.localizedDescription : gitMessage
                    } else {
                        message = error.localizedDescription
                    }
                    BannerManager.shared.show(message: message, style: .error, duration: 5)
                }
            }
        }
    }

}
