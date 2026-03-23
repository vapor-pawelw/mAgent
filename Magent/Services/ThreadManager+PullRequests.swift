import Foundation
import MagentCore

extension ThreadManager {

    struct PullRequestActionTarget {
        let url: URL
        let provider: GitHostingProvider
        let isCreation: Bool
    }

    private func cachedPullRequestRemote(for projectId: UUID, repoPath: String) async -> GitRemote? {
        if let cached = _cachedRemoteByProjectId[projectId] {
            return cached
        }

        let remotes = await git.getRemotes(repoPath: repoPath)
        let chosen = remotes.first(where: { $0.name == "origin" && $0.provider != .unknown })
            ?? remotes.first(where: { $0.provider != .unknown })
        if let chosen {
            _cachedRemoteByProjectId[projectId] = chosen
        }
        return chosen
    }

    private func updatePullRequestLookup(_ result: PullRequestLookupResult, forThreadId threadId: UUID) async {
        let info: PullRequestInfo?
        let status: PullRequestLookupStatus

        switch result {
        case .found(let foundInfo):
            info = foundInfo
            status = .found
        case .notFound:
            info = nil
            status = .notFound
        case .unavailable:
            info = nil
            status = .unavailable
        }

        guard let index = threads.firstIndex(where: { $0.id == threadId }),
              threads[index].pullRequestInfo != info || threads[index].pullRequestLookupStatus != status else {
            return
        }

        threads[index].pullRequestInfo = info
        threads[index].pullRequestLookupStatus = status
        savePRInfoToCache(info: info, thread: threads[index])
        await MainActor.run {
            delegate?.threadManager(self, didUpdateThreads: threads)
            NotificationCenter.default.post(name: .magentPullRequestInfoChanged, object: nil)
        }
    }

    private func normalizedPullRequestTargetBranch(for thread: MagentThread, project: Project) -> String {
        let sourceBranch = thread.actualBranch ?? thread.branchName

        let baseCandidate = resolveBaseBranch(for: thread)
        let normalizedBase = baseCandidate.hasPrefix("origin/")
            ? String(baseCandidate.dropFirst("origin/".count))
            : baseCandidate
        if !normalizedBase.isEmpty, normalizedBase != sourceBranch {
            return normalizedBase
        }

        if let configuredDefault = project.defaultBranch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configuredDefault.isEmpty,
           configuredDefault != sourceBranch {
            return configuredDefault
        }

        return "main"
    }

    func resolvePullRequestActionTarget(for thread: MagentThread) async -> PullRequestActionTarget? {
        if let info = thread.pullRequestInfo {
            return PullRequestActionTarget(
                url: info.url,
                provider: info.provider,
                isCreation: false
            )
        }

        let settings = persistence.loadSettings()
        guard let project = settings.projects.first(where: { $0.id == thread.projectId }),
              let remote = await cachedPullRequestRemote(for: project.id, repoPath: project.repoPath) else {
            return nil
        }

        guard !thread.isMain, thread.pullRequestLookupStatus == .notFound else {
            return nil
        }

        let sourceBranch = thread.actualBranch ?? thread.branchName
        let targetBranch = normalizedPullRequestTargetBranch(for: thread, project: project)
        let title = thread.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = remote.createPullRequestURL(sourceBranch: sourceBranch, targetBranch: targetBranch, title: title) else {
            return nil
        }
        return PullRequestActionTarget(
            url: url,
            provider: remote.provider,
            isCreation: true
        )
    }

    /// Returns `true` if the sync completed without errors.
    @discardableResult
    func runPRSyncTick() async -> Bool {
        guard !isPRSyncRunning else { return true }
        isPRSyncRunning = true
        defer { isPRSyncRunning = false }

        let settings = persistence.loadSettings()
        for project in settings.projects where _cachedRemoteByProjectId[project.id] == nil {
            _ = await cachedPullRequestRemote(for: project.id, repoPath: project.repoPath)
        }

        let snapshot = threads.filter { !$0.isArchived && !$0.isMain }
        var changed = false
        var hadErrors = false
        for thread in snapshot {
            guard let project = settings.projects.first(where: { $0.id == thread.projectId }) else {
                continue
            }

            guard let remote = await cachedPullRequestRemote(for: project.id, repoPath: project.repoPath) else {
                guard let i = threads.firstIndex(where: { $0.id == thread.id }) else {
                    continue
                }
                if threads[i].pullRequestInfo != nil || threads[i].pullRequestLookupStatus != .unavailable {
                    threads[i].pullRequestInfo = nil
                    threads[i].pullRequestLookupStatus = .unavailable
                    changed = true
                }
                continue
            }

            let branch = thread.actualBranch ?? thread.branchName
            let info: PullRequestInfo?
            let status: PullRequestLookupStatus
            do {
                let lookupResult = try await git.lookupPullRequest(remote: remote, branch: branch)
                switch lookupResult {
                case .found(let foundInfo):
                    info = foundInfo
                    status = .found
                case .notFound:
                    info = nil
                    status = .notFound
                case .unavailable:
                    info = nil
                    status = .unavailable
                }
            } catch {
                hadErrors = true
                info = nil
                status = .unavailable
            }
            guard let i = threads.firstIndex(where: { $0.id == thread.id }) else { continue }
            if threads[i].pullRequestInfo != info || threads[i].pullRequestLookupStatus != status {
                threads[i].pullRequestInfo = info
                threads[i].pullRequestLookupStatus = status
                savePRInfoToCache(info: info, thread: threads[i])
                changed = true
            }

            // Yield between threads so the background pass doesn't starve other work.
            await Task.yield()
        }

        if changed {
            await MainActor.run {
                delegate?.threadManager(self, didUpdateThreads: threads)
                NotificationCenter.default.post(name: .magentPullRequestInfoChanged, object: nil)
            }
        }

        prunePRCache()
        return !hadErrors
    }

    /// Refreshes PR status for a single thread (called on thread selection).
    func refreshPRForSelectedThread(_ thread: MagentThread) {
        guard !thread.isMain else { return }
        Task {
            // Skip if a bulk sync is already running — it will cover this thread.
            guard !isPRSyncRunning else { return }

            let settings = persistence.loadSettings()
            guard let project = settings.projects.first(where: { $0.id == thread.projectId }),
                  let remote = await cachedPullRequestRemote(for: project.id, repoPath: project.repoPath) else {
                await updatePullRequestLookup(.unavailable, forThreadId: thread.id)
                return
            }

            let branch = thread.actualBranch ?? thread.branchName
            do {
                let lookupResult = try await git.lookupPullRequest(remote: remote, branch: branch)
                await updatePullRequestLookup(lookupResult, forThreadId: thread.id)
            } catch {
                await updatePullRequestLookup(.unavailable, forThreadId: thread.id)
            }
        }
    }

    // MARK: - PR Cache

    func loadPRCacheIfNeeded() {
        guard !prCacheLoaded else { return }
        prCache = persistence.loadPRCache()
        prCacheLoaded = true
    }

    /// Populates `pullRequestInfo` on all active threads from the file cache.
    /// Called at startup before the first live PR sync tick, so PR indicators appear immediately.
    func populatePRInfoFromCache() {
        loadPRCacheIfNeeded()
        guard !prCache.isEmpty else { return }

        var changed = false
        for i in threads.indices where !threads[i].isArchived && threads[i].pullRequestInfo == nil {
            let branch = threads[i].actualBranch ?? threads[i].branchName
            if let cached = prCache[branch] {
                threads[i].pullRequestInfo = cached.toPullRequestInfo()
                threads[i].pullRequestLookupStatus = .found
                changed = true
            }
        }
        if changed {
            Task { @MainActor in
                delegate?.threadManager(self, didUpdateThreads: threads)
                NotificationCenter.default.post(name: .magentPullRequestInfoChanged, object: nil)
            }
        }
    }

    private func savePRInfoToCache(info: PullRequestInfo?, thread: MagentThread) {
        loadPRCacheIfNeeded()
        let branch = thread.actualBranch ?? thread.branchName
        if let info {
            prCache[branch] = PullRequestCacheEntry(from: info)
        } else {
            prCache.removeValue(forKey: branch)
        }
        persistence.savePRCache(prCache)
    }

    private func prunePRCache() {
        loadPRCacheIfNeeded()
        let activeBranches = Set(
            threads
                .filter { !$0.isArchived }
                .map { $0.actualBranch ?? $0.branchName }
        )
        let before = prCache.count
        prCache = prCache.filter { activeBranches.contains($0.key) }
        if prCache.count != before {
            persistence.savePRCache(prCache)
        }
    }
}
