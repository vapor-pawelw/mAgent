import Cocoa

extension SettingsProjectsViewController {

    // MARK: - Jira Field Handlers

    @objc func jiraProjectKeyChanged() {
        guard let index = selectedProjectIndex else { return }
        let value = jiraProjectKeyField.stringValue.trimmingCharacters(in: .whitespaces).uppercased()
        settings.projects[index].jiraProjectKey = value.isEmpty ? nil : value
        jiraProjectKeyField.stringValue = value
        try? persistence.saveSettings(settings)
    }

    @objc func jiraBoardChanged() {
        guard let index = selectedProjectIndex else { return }
        let selected = jiraBoardPopup.indexOfSelectedItem
        if selected >= 0, selected < jiraBoards.count {
            let board = jiraBoards[selected]
            settings.projects[index].jiraBoardId = board.id
            settings.projects[index].jiraBoardName = board.name
        } else {
            settings.projects[index].jiraBoardId = nil
            settings.projects[index].jiraBoardName = nil
        }
        try? persistence.saveSettings(settings)
    }

    @objc func refreshBoardsTapped() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            jiraBoardPopup.removeAllItems()
            jiraBoardPopup.addItem(withTitle: "Loading...")

            do {
                let boards = try await JiraService.shared.listBoards()
                self.jiraBoards = boards

                jiraBoardPopup.removeAllItems()
                if boards.isEmpty {
                    jiraBoardPopup.addItem(withTitle: "No boards found")
                } else {
                    for board in boards {
                        jiraBoardPopup.addItem(withTitle: "\(board.name) (#\(board.id))")
                    }
                    // Select current board if set
                    if let index = selectedProjectIndex,
                       let currentId = settings.projects[index].jiraBoardId,
                       let boardIndex = boards.firstIndex(where: { $0.id == currentId }) {
                        jiraBoardPopup.selectItem(at: boardIndex)
                    }
                }
            } catch {
                jiraBoardPopup.removeAllItems()
                jiraBoardPopup.addItem(withTitle: "Error: \(error.localizedDescription)")
            }
        }
    }

    @objc func jiraAssigneeChanged() {
        guard let index = selectedProjectIndex else { return }
        let value = jiraAssigneeField.stringValue.trimmingCharacters(in: .whitespaces)
        settings.projects[index].jiraAssigneeAccountId = value.isEmpty ? nil : value
        try? persistence.saveSettings(settings)
    }

    // MARK: - Sync

    @objc func syncSectionsFromJiraTapped() {
        guard let index = selectedProjectIndex else { return }
        let project = settings.projects[index]

        guard project.jiraProjectKey?.isEmpty == false else {
            BannerManager.shared.show(message: "Set a Jira project key first", style: .warning, duration: 3.0)
            return
        }

        jiraSyncButton.isEnabled = false
        jiraSyncButton.title = "Syncing..."

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                jiraSyncButton.isEnabled = true
                jiraSyncButton.title = "Sync Sections from Jira"
            }

            do {
                let sections = try await ThreadManager.shared.syncSectionsFromJira(project: project)
                guard !sections.isEmpty else {
                    BannerManager.shared.show(message: "No statuses found for \(project.jiraProjectKey ?? "")", style: .warning, duration: 3.0)
                    return
                }

                settings.projects[index].threadSections = sections
                settings.projects[index].jiraAcknowledgedStatuses = nil
                try? persistence.saveSettings(settings)
                NotificationCenter.default.post(name: .magentSectionsDidChange, object: nil)

                // Update sections card UI
                sectionsModePopup?.selectItem(at: 1)
                updateSectionsVisibilityControls(for: settings.projects[index])
                sectionsTableView?.reloadData()
                refreshDefaultSectionPopup(for: settings.projects[index])

                BannerManager.shared.show(
                    message: "Created \(sections.count) sections from Jira statuses",
                    style: .info,
                    duration: 3.0
                )
            } catch {
                BannerManager.shared.show(
                    message: "Failed to sync: \(error.localizedDescription)",
                    style: .error,
                    duration: 5.0
                )
            }
        }
    }

    @objc func jiraAutoSyncToggled() {
        guard let index = selectedProjectIndex else { return }
        let enabling = jiraAutoSyncCheckbox.state == .on

        if enabling {
            let project = settings.projects[index]
            var missing: [String] = []
            if project.jiraProjectKey?.isEmpty != false { missing.append("Project Key") }
            if project.jiraAssigneeAccountId?.isEmpty != false { missing.append("Assignee Account ID") }
            let siteURL = project.jiraSiteURL ?? settings.jiraSiteURL
            if siteURL.isEmpty { missing.append("Jira Site URL (set in Settings > Jira)") }

            if !missing.isEmpty {
                jiraAutoSyncCheckbox.state = .off
                BannerManager.shared.show(
                    message: "Cannot enable sync — missing: \(missing.joined(separator: ", "))",
                    style: .warning,
                    duration: 5.0
                )
                return
            }
        }

        settings.projects[index].jiraSyncEnabled = enabling
        try? persistence.saveSettings(settings)

        // Auto-create project sections from Jira when enabling sync and no custom sections exist
        if enabling, settings.projects[index].threadSections == nil {
            let project = settings.projects[index]
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let sections = try await ThreadManager.shared.syncSectionsFromJira(project: project)
                    guard !sections.isEmpty else { return }
                    settings.projects[index].threadSections = sections
                    try? persistence.saveSettings(settings)
                    NotificationCenter.default.post(name: .magentSectionsDidChange, object: nil)

                    // Update sections card UI
                    sectionsModePopup?.selectItem(at: 1)
                    updateSectionsVisibilityControls(for: settings.projects[index])
                    sectionsTableView?.reloadData()
                    refreshDefaultSectionPopup(for: settings.projects[index])

                    BannerManager.shared.show(
                        message: "Created \(sections.count) sections from Jira statuses",
                        style: .info,
                        duration: 3.0
                    )
                } catch {
                    // Non-critical — sync will retry on next tick
                }
            }
        }
    }
}
