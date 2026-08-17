import Foundation
import MagentCore

@MainActor
final class CodexAppProjectSyncCoordinator {
    static let shared = CodexAppProjectSyncCoordinator()

    private let persistence = PersistenceService.shared
    private var observers: [NSObjectProtocol] = []
    private var scheduledTask: Task<Void, Never>?
    private var statePollTimer: Timer?
    private var lastStateFingerprint: CodexAppProjectStateFingerprint?
    private var isSynchronizing = false
    private var needsAnotherPass = false

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .magentCodexProjectSyncNeeded, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleSync()
                }
            })
        lastStateFingerprint = CodexAppProjectSyncService.shared.stateFingerprint()
        statePollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollCodexState()
            }
        }
        if let statePollTimer {
            RunLoop.main.add(statePollTimer, forMode: .common)
        }
        scheduleSync(delay: 1.0)
    }

    func scheduleSync(delay: TimeInterval = 0.3) {
        guard !isSynchronizing else {
            needsAnotherPass = true
            return
        }
        scheduledTask?.cancel()
        scheduledTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.synchronizeNow()
        }
    }

    private func synchronizeNow() async {
        guard !isSynchronizing else { return }
        let settings = persistence.loadSettings()
        guard settings.syncCodexAppProjects else { return }

        let assignments = codexAssignments(projects: settings.projects)
        guard settings.availableActiveAgents.contains(.codex) || !assignments.isEmpty else { return }

        isSynchronizing = true
        defer {
            isSynchronizing = false
            if needsAnotherPass {
                needsAnotherPass = false
                scheduleSync()
            }
        }

        do {
            let importCandidates = try CodexAppProjectSyncService.shared.synchronize(
                projects: settings.projects,
                assignments: assignments
            )
            let importedProjects = await importGitRepositories(
                at: importCandidates,
                excluding: settings.codexAppProjectImportExclusions
            )
            guard !importedProjects.isEmpty else { return }

            NotificationCenter.default.post(name: .magentSettingsDidChange, object: nil)
            for project in importedProjects {
                _ = try? await ThreadManager.shared.createMainThread(project: project)
            }

            let refreshedSettings = persistence.loadSettings()
            _ = try CodexAppProjectSyncService.shared.synchronize(
                projects: refreshedSettings.projects,
                assignments: codexAssignments(projects: refreshedSettings.projects)
            )
        } catch {
            NSLog("[CodexProjectSync] Synchronization failed: %@", error.localizedDescription)
        }
    }

    private func pollCodexState() {
        let fingerprint = CodexAppProjectSyncService.shared.stateFingerprint()
        guard fingerprint != lastStateFingerprint else { return }
        lastStateFingerprint = fingerprint
        scheduleSync()
    }

    private func codexAssignments(projects: [Project]) -> [CodexAppThreadProjectAssignment] {
        let projectPaths = Dictionary(
            projects.map { ($0.id, $0.repoPath) },
            uniquingKeysWith: { first, _ in first }
        )
        return ThreadManager.shared.threads.flatMap { thread -> [CodexAppThreadProjectAssignment] in
            guard !thread.isArchived, let projectPath = projectPaths[thread.projectId] else { return [] }
            return thread.sessionConversationIDs.compactMap { sessionName, conversationID in
                guard ThreadManager.shared.agentType(for: thread, sessionName: sessionName) == .codex else {
                    return nil
                }
                return CodexAppThreadProjectAssignment(
                    threadID: conversationID,
                    projectPath: projectPath
                )
            }
        }
    }

    private func importGitRepositories(at paths: [String], excluding excludedPaths: [String]) async -> [Project] {
        var candidates: [(path: String, defaultBranch: String?)] = []
        var seenPaths = Set(persistence.loadSettings().projects.map { normalizedPath($0.repoPath) })
        let normalizedExcludedPaths = Set(excludedPaths.map(normalizedPath))

        for path in paths {
            guard await GitService.shared.isGitRepository(at: path) else { continue }
            let worktrees = try? await GitService.shared.listWorktrees(repoPath: path)
            let repositoryPath = normalizedPath(
                worktrees?.first(where: { !$0.isBareStem })?.path ?? path
            )
            guard !normalizedExcludedPaths.contains(repositoryPath) else { continue }
            guard seenPaths.insert(repositoryPath).inserted else { continue }
            let defaultBranch = await GitService.shared.detectDefaultBranch(repoPath: repositoryPath)
            candidates.append((repositoryPath, defaultBranch))
        }

        guard !candidates.isEmpty else { return [] }
        var latestSettings = persistence.loadSettings()
        let registeredPaths = Set(latestSettings.projects.map { normalizedPath($0.repoPath) })
        let projects = candidates.compactMap { candidate -> Project? in
            guard !registeredPaths.contains(candidate.path) else { return nil }
            return Project(
                name: URL(fileURLWithPath: candidate.path).lastPathComponent,
                repoPath: candidate.path,
                worktreesBasePath: Project.suggestedWorktreesPath(for: candidate.path),
                defaultBranch: candidate.defaultBranch,
                agentType: .codex
            )
        }
        guard !projects.isEmpty else { return [] }

        latestSettings.projects.append(contentsOf: projects)
        do {
            try persistence.saveSettings(latestSettings)
            return projects
        } catch {
            NSLog("[CodexProjectSync] Could not import Codex App projects: %@", error.localizedDescription)
            return []
        }
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
