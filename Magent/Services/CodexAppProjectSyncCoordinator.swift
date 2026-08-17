import Foundation
import MagentCore

@MainActor
final class CodexAppProjectSyncCoordinator {
    static let shared = CodexAppProjectSyncCoordinator()

    private let persistence = PersistenceService.shared
    private weak var appCoordinator: AppCoordinator?
    private var observers: [NSObjectProtocol] = []
    private var scheduledTask: Task<Void, Never>?
    private var statePollTimer: Timer?
    private var lastStateFingerprint: CodexAppProjectStateFingerprint?
    private var repositoryResolutionCache: [UUID: (configuredPath: String, resolution: MagentProjectRepositoryResolution)] = [:]
    private var exclusionIdentityCache: [String: String] = [:]
    private var isSynchronizing = false
    private var needsAnotherPass = false

    func start(appCoordinator: AppCoordinator) {
        self.appCoordinator = appCoordinator
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
        guard !isSynchronizing else {
            needsAnotherPass = true
            return
        }
        isSynchronizing = true
        defer {
            isSynchronizing = false
            if needsAnotherPass {
                needsAnotherPass = false
                scheduleSync()
            }
        }

        var settings = persistence.loadSettings()
        guard let reconciliation = await reconcileDuplicateProjects(in: settings) else { return }
        settings = reconciliation.settings
        guard settings.syncCodexAppProjects else { return }

        let assignments = codexAssignments(projects: settings.projects)
        guard settings.availableActiveAgents.contains(.codex) || !assignments.isEmpty else { return }

        do {
            let importCandidates = try CodexAppProjectSyncService.shared.synchronize(
                projects: settings.projects,
                assignments: assignments
            )
            let importedProjects = reconciliation.hasUnresolvedProjects ? [] : await importGitRepositories(
                    at: importCandidates,
                    excluding: settings.codexAppProjectImportExclusions,
                    existingRepositoryIdentities: reconciliation.repositoryIdentities,
                    expectedProjects: settings.projects
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

    private func reconcileDuplicateProjects(
        in settings: AppSettings
    ) async -> (settings: AppSettings, repositoryIdentities: Set<String>, hasUnresolvedProjects: Bool)? {
        var resolutions: [MagentProjectRepositoryResolution] = []
        for project in settings.projects {
            if let cached = repositoryResolutionCache[project.id],
               cached.configuredPath == project.repoPath,
               FileManager.default.fileExists(atPath: project.repoPath),
               FileManager.default.fileExists(atPath: cached.resolution.canonicalProjectPath) {
                resolutions.append(cached.resolution)
                continue
            }
            let identity: GitRepositoryIdentity
            do {
                identity = try await GitService.shared.repositoryIdentity(at: project.repoPath)
            } catch {
                repositoryResolutionCache.removeValue(forKey: project.id)
                NSLog(
                    "[CodexProjectSync] Could not resolve project repository identity for %@: %@",
                    project.repoPath,
                    error.localizedDescription
                )
                continue
            }
            let resolution = MagentProjectRepositoryResolution(
                projectID: project.id,
                repositoryIdentity: identity.projectIdentity,
                canonicalProjectPath: identity.canonicalProjectPath
            )
            repositoryResolutionCache[project.id] = (project.repoPath, resolution)
            resolutions.append(resolution)
        }
        let currentProjectIDs = Set(settings.projects.map(\.id))
        repositoryResolutionCache = repositoryResolutionCache.filter { currentProjectIDs.contains($0.key) }

        let repositoryIdentities = Set(resolutions.map(\.repositoryIdentity))
        let hasUnresolvedProjects = resolutions.count != settings.projects.count
        let plan = MagentProjectDeduplicator.plan(
            projects: settings.projects,
            resolutions: resolutions
        )
        guard plan.projects != settings.projects || !plan.projectIDReplacements.isEmpty else {
            return (settings, repositoryIdentities, hasUnresolvedProjects)
        }
        guard let appCoordinator else {
            NSLog("[CodexProjectSync] Project migration skipped because AppCoordinator is unavailable")
            return nil
        }

        var latestSettings = persistence.loadSettings()
        guard latestSettings.projects == settings.projects else {
            needsAnotherPass = true
            return nil
        }

        let projectByID = Dictionary(
            settings.projects.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let migrateThread: (MagentThread) -> MagentThread = { thread in
            MagentProjectThreadMigrator.migrate(thread, projectsByID: projectByID, plan: plan)
        }
        let persistedThreadsBeforeMigration = persistence.loadThreads()
        var allThreads = persistedThreadsBeforeMigration
        for runtimeThread in ThreadManager.shared.threads {
            if let index = allThreads.firstIndex(where: { $0.id == runtimeThread.id }) {
                allThreads[index] = runtimeThread
            } else {
                allThreads.append(runtimeThread)
            }
        }
        let activeThreads = allThreads.filter { !$0.isArchived }.map(migrateThread)
        let consolidatedActiveThreads = appCoordinator.consolidateDuplicateThreads(activeThreads)
        let archivedThreads = allThreads.filter(\.isArchived).map(migrateThread)

        latestSettings.projects = plan.projects
        do {
            try persistence.saveThreads(consolidatedActiveThreads + archivedThreads)
            try persistence.saveSettings(latestSettings)
            ThreadManager.shared.applyProjectMigrationThreads(consolidatedActiveThreads)
            await ThreadManager.shared.ensureMainThreads()
            NotificationCenter.default.post(name: .magentSettingsDidChange, object: nil)
            repositoryResolutionCache = repositoryResolutionCache.filter { projectID, _ in
                latestSettings.projects.contains(where: { $0.id == projectID })
            }
            return (latestSettings, repositoryIdentities, hasUnresolvedProjects)
        } catch {
            do {
                try persistence.saveThreads(persistedThreadsBeforeMigration)
            } catch {
                NSLog("[CodexProjectSync] Could not roll back threads after project consolidation failure: %@", error.localizedDescription)
            }
            NSLog("[CodexProjectSync] Could not consolidate duplicate projects: %@", error.localizedDescription)
            return (settings, repositoryIdentities, hasUnresolvedProjects)
        }
    }

    private func importGitRepositories(
        at paths: [String],
        excluding excludedPaths: [String],
        existingRepositoryIdentities: Set<String>,
        expectedProjects: [Project]
    ) async -> [Project] {
        guard !paths.isEmpty else { return [] }
        var candidates: [(path: String, defaultBranch: String?)] = []
        var seenRepositoryIdentities = existingRepositoryIdentities
        let normalizedExcludedPaths = Set(excludedPaths.map(normalizedPath))
        var excludedRepositoryIdentities = Set<String>()
        for path in excludedPaths {
            if let cachedIdentity = exclusionIdentityCache[path] {
                excludedRepositoryIdentities.insert(cachedIdentity)
            } else if let identity = try? await GitService.shared.repositoryIdentity(at: path) {
                exclusionIdentityCache[path] = identity.projectIdentity
                excludedRepositoryIdentities.insert(identity.projectIdentity)
            }
        }
        exclusionIdentityCache = exclusionIdentityCache.filter { excludedPaths.contains($0.key) }

        for path in paths {
            guard let repository = try? await GitService.shared.repositoryIdentity(at: path) else { continue }
            let repositoryPath = normalizedPath(repository.canonicalProjectPath)
            guard !normalizedExcludedPaths.contains(repositoryPath) else { continue }
            guard !excludedRepositoryIdentities.contains(repository.projectIdentity) else { continue }
            guard seenRepositoryIdentities.insert(repository.projectIdentity).inserted else { continue }
            let defaultBranch = await GitService.shared.detectDefaultBranch(repoPath: repositoryPath)
            candidates.append((repositoryPath, defaultBranch))
        }

        guard !candidates.isEmpty else { return [] }
        var latestSettings = persistence.loadSettings()
        guard latestSettings.projects == expectedProjects else {
            needsAnotherPass = true
            return []
        }
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
