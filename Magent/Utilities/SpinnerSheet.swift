import AppKit

extension NSViewController {

    /// Checks git state and presents the appropriate confirmation dialog before archiving a thread.
    /// Handles agent-busy, dirty worktree, and clean-and-merged cases.
    func confirmAndArchiveThread(_ thread: MagentThread) {
        let threadManager = ThreadManager.shared
        let baseBranch = threadManager.resolveBaseBranch(for: thread)

        Task {
            let git = GitService.shared
            let clean = await git.isClean(worktreePath: thread.worktreePath)
            let merged = await git.isMergedInto(worktreePath: thread.worktreePath, baseBranch: baseBranch)

            await MainActor.run {
                let liveThread = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
                let agentBusy = liveThread.hasAgentBusy

                if agentBusy {
                    let alert = NSAlert()
                    alert.messageText = "Archive Thread"
                    alert.informativeText = "An agent in \"\(thread.name)\" is currently busy. Archiving will terminate the running agent and remove the worktree directory. The git branch \"\(thread.branchName)\" will be kept."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Archive Anyway")
                    alert.addButton(withTitle: "Cancel")

                    let response = alert.runModal()
                    guard response == .alertFirstButtonReturn else { return }

                    self.performWithSpinner(message: "Archiving thread...", errorTitle: "Archive Failed") {
                        try await threadManager.archiveThread(thread)
                    }
                } else if clean && merged {
                    self.performWithSpinner(message: "Archiving thread...", errorTitle: "Archive Failed") {
                        try await threadManager.archiveThread(thread)
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Archive Thread"
                    var reasons: [String] = []
                    if !clean { reasons.append("uncommitted changes") }
                    if !merged { reasons.append("commits not in \(baseBranch)") }
                    alert.informativeText = "The thread \"\(thread.name)\" has \(reasons.joined(separator: " and ")). Archiving will remove its worktree directory but keep the git branch \"\(thread.branchName)\"."
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "Archive")
                    alert.addButton(withTitle: "Cancel")

                    let response = alert.runModal()
                    guard response == .alertFirstButtonReturn else { return }

                    self.performWithSpinner(message: "Archiving thread...", errorTitle: "Archive Failed") {
                        try await threadManager.archiveThread(thread)
                    }
                }
            }
        }
    }

    /// Presents a modal sheet with a spinner and label, runs the async work block,
    /// then dismisses the sheet. Shows an alert on failure.
    func performWithSpinner(message: String, errorTitle: String, work: @escaping () async throws -> Void) {
        guard let window = view.window else { return }

        let sheetVC = NSViewController()
        sheetVC.view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 80))

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(resource: .textSecondary)
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        sheetVC.view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: sheetVC.view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: sheetVC.view.centerYAnchor),
        ])

        window.contentViewController?.presentAsSheet(sheetVC)

        Task {
            do {
                try await work()
                await MainActor.run {
                    window.contentViewController?.dismiss(sheetVC)
                }
            } catch {
                await MainActor.run {
                    window.contentViewController?.dismiss(sheetVC)
                    let alert = NSAlert()
                    alert.messageText = errorTitle
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}
